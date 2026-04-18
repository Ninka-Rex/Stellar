// Chrome MV3 service worker - Stellar extension
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

import { handleDownloadCreated, recordModifierKey, forceIntercept } from "./shared/interceptor.js";
import { ping, requestDownload, shouldIntercept, syncSettingsFromApp } from "./shared/messaging.js";

const ICONS_ENABLED = {
    16: "icons/milky-way.png",
    48: "icons/milky-way.png",
    128: "icons/milky-way.png",
};

const ICONS_DISABLED = {
    16: "icons/milky-way-bw.png",
    48: "icons/milky-way-bw.png",
    128: "icons/milky-way-bw.png",
};

async function refreshIcon() {
    try {
        const stored = await chrome.storage.local.get(["enabled"]);
        const enabled = stored.enabled !== false;
        await chrome.action.setIcon({ path: enabled ? ICONS_ENABLED : ICONS_DISABLED });
    } catch (err) {
        console.warn("[Stellar] Could not refresh extension icon:", err);
    }
}

async function updateConnectionState() {
    try {
        const alive = await ping();
        await refreshIcon();
        if (!alive) {
            console.warn("[Stellar] Native host replied, but not with a ready response.");
        }
    } catch (err) {
        await refreshIcon();
        console.warn("[Stellar] Native host ping failed during icon refresh:", err?.message ?? err);
    }
}

// Download interception
chrome.downloads.onCreated.addListener((item) => {
    handleDownloadCreated(item);
});

// Handle modifier key tracking from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "recordModifierKey") {
        recordModifierKey(message.modifierKey);
        sendResponse({ ok: true });
        return true;
    }

    if (message.type === "getSettings") {
        (async () => {
            try {
                const stored = await chrome.storage.local.get([
                    "monitoredExtensions",
                    "excludedSites",
                    "excludedAddresses",
                    "enabled"
                ]);
                sendResponse({
                    type: "settings",
                    monitoredExtensions: stored.monitoredExtensions ?? [],
                    excludedSites: stored.excludedSites ?? [],
                    excludedAddresses: stored.excludedAddresses ?? [],
                    enabled: stored.enabled !== false
                });
            } catch (err) {
                sendResponse({ type: "settings", enabled: true, error: err?.message ?? "unknown" });
            }
        })();
        return true;
    }

    if (message.type === "ping") {
        (async () => {
            try {
                const alive = await ping();
                sendResponse({ alive });
            } catch (err) {
                sendResponse({ alive: false, error: err?.message ?? "unknown" });
            }
        })();
        return true;
    }

    if (message.type === "focus") {
        chrome.runtime.sendNativeMessage("com.stellar.downloadmanager", { type: "focus" }, (response) => {
            if (chrome.runtime.lastError) {
                sendResponse({ ok: false, error: chrome.runtime.lastError.message });
            } else {
                sendResponse({ ok: true, response });
            }
        });
        return true;
    }

    if (message.type === "setEnabled") {
        chrome.storage.local.set({ enabled: !!message.value }, () => {
            if (chrome.runtime.lastError) {
                sendResponse({ ok: false, error: chrome.runtime.lastError.message });
            } else {
                sendResponse({ ok: true });
            }
        });
        return true;
    }

    if (message.type === "interceptLinkClick") {
        (async () => {
            try {
                const alive = await ping();
                if (!alive) {
                    sendResponse({ ok: false, reason: "native-host-unavailable" });
                    return;
                }
                const url = message.url || "";
                const filename = message.filename || "";
                const explicitIntent = !!message.explicitIntent;
                const allowed = forceIntercept(url) || await shouldIntercept(url, "", filename, explicitIntent);
                if (!allowed) {
                    sendResponse({ ok: false, reason: "not-intercepted" });
                    return;
                }
                let cookieHeader = message.cookies || "";
                if (!cookieHeader) {
                    try {
                        const urlObj = new URL(url);
                        const cookieUrls = [url];
                        const parts = urlObj.hostname.split(".");
                        for (let i = 1; i < parts.length - 1; i++)
                            cookieUrls.push(`${urlObj.protocol}//${parts.slice(i).join(".")}/`);
                        const seen = new Set();
                        const allCookies = [];
                        for (const cu of cookieUrls) {
                            const batch = await chrome.cookies.getAll({ url: cu });
                            for (const c of batch) {
                                if (!seen.has(c.name)) { seen.add(c.name); allCookies.push(c); }
                            }
                        }
                        cookieHeader = allCookies.map(c => `${c.name}=${c.value}`).join("; ");
                    } catch (err) {
                        console.warn("[Stellar] Could not collect cookies for intercepted link:", err);
                    }
                }
                await requestDownload({
                    url,
                    filename,
                    referrer: message.referrer || "",
                    pageUrl: message.pageUrl || "",
                    cookies: cookieHeader,
                    modifierKey: 0,
                });
                sendResponse({ ok: true });
            } catch (err) {
                console.error("[Stellar] Failed to process interceptLinkClick:", err);
                sendResponse({ ok: false, error: err?.message ?? "unknown" });
            }
        })();
        return true;
    }
});

// Context menu
chrome.runtime.onInstalled.addListener(async () => {
    chrome.contextMenus.create({
        id: "stellar-download-link",
        title: "Download with Stellar",
        contexts: ["link"],
    });
    chrome.contextMenus.create({
        id: "stellar-download-media",
        title: "Download with Stellar",
        contexts: ["video", "audio", "image"],
    });
    await syncSettingsFromApp();
    await refreshIcon();
});

chrome.contextMenus.onClicked.addListener(async (info) => {
    const url = info.linkUrl || info.srcUrl || info.pageUrl;
    if (!url) return;
    let cookieHeader = "";
    try {
        const urlObj = new URL(url);
        const cookieUrls = [url];
        const parts = urlObj.hostname.split(".");
        for (let i = 1; i < parts.length - 1; i++)
            cookieUrls.push(`${urlObj.protocol}//${parts.slice(i).join(".")}/`);
        const seen = new Set();
        const allCookies = [];
        for (const cu of cookieUrls) {
            const batch = await chrome.cookies.getAll({ url: cu });
            for (const c of batch) {
                if (!seen.has(c.name)) { seen.add(c.name); allCookies.push(c); }
            }
        }
        cookieHeader = allCookies.map(c => `${c.name}=${c.value}`).join("; ");
    } catch { /* cookies permission may not be granted */ }
    try {
        await requestDownload({ url, referrer: info.frameUrl ?? info.pageUrl ?? "", pageUrl: info.pageUrl ?? "", cookies: cookieHeader });
    } catch (err) {
        console.error("[Stellar] Context menu download failed:", err);
    }
});

chrome.runtime.onStartup.addListener(async () => {
    await syncSettingsFromApp();
    await refreshIcon();
});

chrome.storage.onChanged.addListener(async (changes, areaName) => {
    if (areaName === "local" && Object.prototype.hasOwnProperty.call(changes, "enabled")) {
        await refreshIcon();
    }
});

updateConnectionState();
