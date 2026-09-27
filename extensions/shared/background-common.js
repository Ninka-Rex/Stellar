// Stellar Download Manager — Background logic shared by Chrome and Firefox
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import { ext } from "./ext.js";
import { focusApp, pingNative, sendDownload, sendImportLinks } from "./native.js";
import { hasSiteEntry, isHostExcluded, loadedSettings, onSettingsReloaded, setEnabled, syncFromApp } from "./settings.js";
import { pausedTabs, setSiteExcluded, setTabPaused, siteHostOf } from "./sitecontrol.js";
import { recordClick } from "./clicks.js";
import { isSendableUrl, isTransferableUrl } from "./policy.js";
import { cookieHeaderFor, cookieStoreForTab } from "./cookies.js";

const ALL_SITES = { origins: ["<all_urls>"] };
const DISABLED_ICON = "icons/milky-way-bw.png";

const MENU_LINK = "stellar-download-link";
const MENU_MEDIA = "stellar-download-media";
const MENU_LINKS = "stellar-download-links";

// Without site access (Firefox < 127 does not grant MV3 host permissions at
// install; Chrome users can withhold them) nothing is intercepted, so it is
// surfaced on the toolbar button instead of failing silently.
export function hasSiteAccess() {
    return ext.permissions.contains(ALL_SITES);
}

const DISABLED_ICONS = { 16: DISABLED_ICON, 48: DISABLED_ICON, 128: DISABLED_ICON };
const NO_ACCESS_TITLE = "Stellar needs access to websites to capture downloads. Click to grant it.";

function pageHost(url) {
    try {
        const u = new URL(url);
        return u.protocol === "http:" || u.protocol === "https:" ? u.hostname.toLowerCase() : "";
    } catch {
        return "";
    }
}

async function actionState() {
    const [settings, access, paused] = await Promise.all([loadedSettings(), hasSiteAccess(), pausedTabs()]);
    return { settings, access, paused, icons: ext.runtime.getManifest().icons };
}

// Why interception is off in this tab, or "" when it is on.
function tabOffTitle(tab, state) {
    if (!state.access) return NO_ACCESS_TITLE;
    if (!state.settings.enabled) return "Stellar: interception is off";
    if (state.paused.has(tab.id)) return "Stellar: paused on this tab";
    const host = pageHost(tab.url);
    if (host && isHostExcluded(host, state.settings)) return `Stellar: not intercepting on ${host}`;
    return "";
}

// Tab-specific icon/title override the global ones, so every tab gets explicit
// values (Firefox also resets them whenever the tab navigates).
async function refreshTabAction(tab, state) {
    const off = tabOffTitle(tab, state);
    try {
        await ext.action.setIcon({ tabId: tab.id, path: off ? DISABLED_ICONS : state.icons });
        await ext.action.setTitle({ tabId: tab.id, title: off || "Stellar Download Manager" });
    } catch { /* tab closed meanwhile */ }
}

export async function refreshActionState() {
    try {
        const state = await actionState();
        const on = state.settings.enabled && state.access;
        await ext.action.setIcon({ path: on ? state.icons : DISABLED_ICONS });
        await ext.action.setBadgeText({ text: state.access ? "" : "!" });
        if (!state.access) await ext.action.setBadgeBackgroundColor({ color: "#cc5555" });
        await ext.action.setTitle({ title: state.access ? "Stellar Download Manager" : NO_ACCESS_TITLE });
        const tabs = await ext.tabs.query({});
        await Promise.all(tabs.map((tab) => refreshTabAction(tab, state)));
    } catch (err) {
        console.warn("[Stellar] Could not refresh toolbar button:", err);
    }
}

async function refreshOneTab(tabId) {
    try {
        await refreshTabAction(await ext.tabs.get(tabId), await actionState());
    } catch { /* tab closed */ }
}

// What the popup shows for the tab it was opened on.
async function tabState(tabId, settings) {
    let tab;
    try { tab = await ext.tabs.get(tabId); } catch { return null; }
    const site = siteHostOf(tab.url);
    const host = pageHost(tab.url);
    return {
        site,
        paused: (await pausedTabs()).has(tabId),
        siteExcluded: !!host && isHostExcluded(host, settings),
        // Only an entry naming exactly this site can be undone from the popup;
        // a wildcard pattern belongs to the user and is edited in Stellar.
        siteEntry: !!site && hasSiteEntry(site, settings),
    };
}

function createMenus() {
    // contextMenus.create reports failures through lastError only; reading it in
    // the callback keeps a harmless duplicate from logging an unchecked error.
    const done = () => void ext.runtime.lastError;
    const removal = ext.contextMenus.removeAll();
    const create = () => {
        ext.contextMenus.create({ id: MENU_LINK, title: "Download with Stellar", contexts: ["link"] }, done);
        ext.contextMenus.create({ id: MENU_MEDIA, title: "Download with Stellar", contexts: ["video", "audio", "image"] }, done);
        ext.contextMenus.create({ id: MENU_LINKS, title: "Download all links with Stellar", contexts: ["selection"] }, done);
    };
    // Older Chrome returns undefined here; API calls still execute in order.
    if (removal?.then) return removal.then(create, create);
    create();
    return Promise.resolve();
}

// URL a menu click refers to. Streaming players expose blob:/data: sources that
// cannot be fetched outside the page; for video/audio the page itself is handed
// over so the app can resolve it (yt-dlp).
function menuTargetUrl(info) {
    if (info.menuItemId === MENU_LINK) return isSendableUrl(info.linkUrl) ? info.linkUrl : "";
    if (isTransferableUrl(info.srcUrl)) return info.srcUrl;
    if ((info.mediaType === "video" || info.mediaType === "audio") && isTransferableUrl(info.pageUrl))
        return info.pageUrl;
    return "";
}

async function onMenuClicked(info, tab) {
    const storeId = await cookieStoreForTab(tab?.id);
    const pageUrl = info.pageUrl ?? "";

    if (info.menuItemId === MENU_LINKS) {
        if (!tab || tab.id === undefined) return;
        let links = [];
        try {
            links = await ext.tabs.sendMessage(tab.id, { type: "collectSelectedLinks" },
                                               { frameId: info.frameId ?? 0 });
        } catch (err) {
            console.error("[Stellar] Could not collect selected links:", err);
        }
        // The list comes from a page's DOM: rebuild it from checked fields only.
        const clean = (Array.isArray(links) ? links : [])
            .filter((l) => l && isSendableUrl(l.url))
            .map((l) => ({ url: l.url, text: typeof l.text === "string" ? l.text.slice(0, 300) : "" }));
        if (clean.length === 0) return;
        try {
            await sendImportLinks(clean, {
                referrer: info.frameUrl ?? pageUrl,
                pageUrl,
                cookies: isTransferableUrl(pageUrl) ? await cookieHeaderFor(pageUrl, storeId) : "",
            });
        } catch (err) {
            console.error("[Stellar] Import links failed:", err);
        }
        return;
    }

    const url = menuTargetUrl(info);
    if (!url) return;
    try {
        await sendDownload({
            url,
            referrer: info.frameUrl ?? pageUrl,
            pageUrl,
            cookies: isTransferableUrl(url) ? await cookieHeaderFor(url, storeId) : "",
        });
    } catch (err) {
        console.error("[Stellar] Context menu download failed:", err);
    }
}

// The popup, as opposed to a content script: a content script runs inside a web
// page's process, so it may only report clicks, never change settings.
function isExtensionPage(sender) {
    return !sender.tab && typeof sender.url === "string" && sender.url.startsWith(ext.runtime.getURL(""));
}

function onMessage(message, sender, sendResponse) {
    if (sender.id !== ext.runtime.id || !message || typeof message.type !== "string") return false;
    if (message.type === "linkClick") {
        if (sender.tab) recordClick(message, sender);
        return false;
    }
    if (!isExtensionPage(sender)) return false;

    const reply = (promise) => {
        promise.then(sendResponse, (err) => sendResponse({ ok: false, error: err?.message ?? String(err) }));
        return true; // keep the channel open for the async answer
    };

    const tabId = Number.isInteger(message.tabId) ? message.tabId : -1;
    switch (message.type) {
    case "getState":
        return reply((async () => {
            const [settings, access] = await Promise.all([loadedSettings(), hasSiteAccess()]);
            return {
                ok: true,
                enabled: settings.enabled,
                darkMode: settings.darkMode,
                siteAccess: access,
                tab: tabId >= 0 ? await tabState(tabId, settings) : null,
            };
        })());
    case "setEnabled":
        return reply(setEnabled(message.value === true).then(() => ({ ok: true })));
    case "setTabPaused":
        if (tabId < 0) return false;
        return reply(setTabPaused(tabId, message.paused === true)
            .then(() => refreshOneTab(tabId))
            .then(() => ({ ok: true })));
    case "setSiteExcluded":
        if (tabId < 0) return false;
        // The site is derived from the tab here rather than taken from the
        // message, so only a site the user is actually on can be listed.
        return reply(ext.tabs.get(tabId).then(async (tab) => {
            const site = siteHostOf(tab.url);
            if (!site) throw new Error("This page has no site that can be excluded");
            await setSiteExcluded(site, message.exclude === true);
            return { ok: true };
        }));
    case "ping":
        return reply(pingNative().then((alive) => ({ ok: true, alive }),
                                       (err) => ({ ok: true, alive: false, error: err?.message ?? String(err) })));
    case "focus":
        return reply(focusApp().then(() => ({ ok: true })));
    default:
        return false;
    }
}

export function installCommon() {
    ext.runtime.onMessage.addListener(onMessage);
    ext.contextMenus.onClicked.addListener((info, tab) => {
        onMenuClicked(info, tab).catch((err) => console.error("[Stellar] Menu action failed:", err));
    });
    ext.runtime.onInstalled.addListener(() => {
        createMenus().catch((err) => console.warn("[Stellar] Could not create menus:", err));
        syncFromApp();
        refreshActionState();
    });
    ext.runtime.onStartup.addListener(() => {
        syncFromApp();
        refreshActionState();
    });
    // Syncs reload settings every 30 s; only a change that alters what the
    // toolbar shows is worth walking every tab for.
    let shown = null;
    onSettingsReloaded((settings) => {
        const key = `${settings.enabled}|${settings.excludedSiteEntries.join(" ")}`;
        if (key !== shown) {
            shown = key;
            refreshActionState();
        }
    });
    ext.tabs.onUpdated.addListener((tabId, changeInfo) => {
        if (changeInfo.url || changeInfo.status) refreshOneTab(tabId);
    });
    ext.permissions.onAdded.addListener(refreshActionState);
    ext.permissions.onRemoved.addListener(refreshActionState);
    refreshActionState();
}
