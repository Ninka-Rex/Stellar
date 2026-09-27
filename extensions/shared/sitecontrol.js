// Stellar Download Manager — Per-tab pause and per-site exclusion
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
import { nativeRequest } from "./native.js";
import { mirrorSiteExclusion } from "./settings.js";

// Two scopes, as in the popup:
//   tab pause  — temporary (like IDM's toolbar click): lives in session storage,
//                so it survives the background being unloaded but not a browser
//                restart, and is dropped when the tab closes;
//   site entry — permanent: written to the app's "Don't start downloading
//                automatically from the following sites" list, so it shows up
//                (and can be removed) in Stellar's preferences as well.

const PAUSED_KEY = "pausedTabs";

// Must match AppSettings::normalizedExclusionHost(), which rejects anything else.
const HOST_RE = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$/;

export async function pausedTabs() {
    const stored = await ext.storage.session.get(PAUSED_KEY);
    return new Set(Array.isArray(stored[PAUSED_KEY]) ? stored[PAUSED_KEY].filter(Number.isInteger) : []);
}

// Read-modify-write of one storage key: serialized, or closing a window (many
// onRemoved at once) would lose updates.
let pauseWrites = Promise.resolve();

export function setTabPaused(tabId, paused) {
    const write = pauseWrites.then(async () => {
        const tabs = await pausedTabs();
        if (paused) tabs.add(tabId);
        else if (!tabs.delete(tabId)) return;
        await ext.storage.session.set({ [PAUSED_KEY]: [...tabs] });
    });
    pauseWrites = write.catch(() => {});
    return write;
}

ext.tabs.onRemoved.addListener((tabId) => {
    setTabPaused(tabId, false).catch(() => {});
});

// The site a page belongs to, as offered for exclusion: "www." is dropped so the
// entry covers the whole site (bare entries also match subdomains).
export function siteHostOf(url) {
    let u;
    try { u = new URL(url); } catch { return ""; }
    if (u.protocol !== "http:" && u.protocol !== "https:") return "";
    const host = u.hostname.toLowerCase().replace(/^www\./, "");
    return HOST_RE.test(host) && host.length <= 253 ? host : "";
}

export async function setSiteExcluded(host, exclude) {
    if (!HOST_RE.test(host)) throw new Error("Invalid site");
    const resp = await nativeRequest({ type: "excludeSite", site: host, exclude: !!exclude });
    if (resp?.type !== "ack") throw new Error(resp?.message || "Stellar did not accept the change");
    await mirrorSiteExclusion(host, !!exclude);
}

function isWebUrl(url) {
    return typeof url === "string" && /^https?:/i.test(url);
}

// Resolves the tab(s) a download came from into: whether interception is paused
// there, and the page URL to test against the site list. A download that opens
// in a new tab belongs to the tab (and page) that opened it.
export async function tabContext(tabIds, fallbackPageUrls = []) {
    const paused = await pausedTabs();
    let isPaused = false;
    let pageUrl = "";
    for (const id of tabIds) {
        if (!Number.isInteger(id) || id < 0) continue;
        if (paused.has(id)) isPaused = true;
        let tab;
        try { tab = await ext.tabs.get(id); } catch { continue; }
        if (!pageUrl && isWebUrl(tab.url)) pageUrl = tab.url;
        if (Number.isInteger(tab.openerTabId)) {
            if (paused.has(tab.openerTabId)) isPaused = true;
            if (!pageUrl) {
                try {
                    const opener = await ext.tabs.get(tab.openerTabId);
                    if (isWebUrl(opener.url)) pageUrl = opener.url;
                } catch { /* opener closed */ }
            }
        }
    }
    if (!pageUrl) pageUrl = fallbackPageUrls.find(isWebUrl) || "";
    return { paused: isPaused, pageUrl };
}
