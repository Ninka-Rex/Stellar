// Stellar Download Manager — Firefox Extension
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

"use strict";

const NATIVE_HOST_ID = "com.stellar.downloadmanager";

const ICONS_ENABLED = {
    16: "icons/icon16.png",
    48: "icons/icon48.png",
    128: "icons/icon128.png",
};

const ICONS_DISABLED = {
    16: "icons/milky-way-bw.png",
    48: "icons/milky-way-bw.png",
    128: "icons/milky-way-bw.png",
};

let lastModifierKey = 0;
let lastModifierKeyTime = 0;
const MODIFIER_KEY_TIMEOUT = 10000;

function recordModifierKey(modifierKey) {
    lastModifierKey = modifierKey;
    lastModifierKeyTime = Date.now();
}

function getAndClearModifierKey() {
    const now = Date.now();
    if (now - lastModifierKeyTime >= MODIFIER_KEY_TIMEOUT) return 0;
    const key = lastModifierKey;
    lastModifierKey = 0;
    return key;
}

const DEFAULT_MONITORED_EXTENSIONS = new Set([
    "3gp","7z","aac","ace","aif","apk","arj","asf","avi","bin","bz2",
    "exe","gz","gzip","img","iso","lzh","m4a","m4v","mkv","mov","mp3",
    "mp4","mpa","mpe","mpeg","mpg","msi","msu","ogg","ogv","pdf","plj",
    "pps","ppt","qt","r00","r01","ra","rar","rm","rmvb","sea","sit","sitx",
    "tar","tif","tiff","wav","wma","wmv","z","zip",
    "safetensors","gguf","azw3","unitypackage"
]);

const DEFAULT_EXCLUDED_SITES = [
    "*.update.microsoft.com",
    "download.windowsupdate.com",
    "*.download.windowsupdate.com",
    "siteseal.thawte.com",
    "ecom.cimetz.com",
    "*.voice2page.com",
    "download.sophos.com"
];

const DEFAULT_EXCLUDED_ADDRESSES = [];

const SETTINGS_CACHE_TTL_MS = 5000;
let cachedSettings = null;
let cachedSettingsTime = 0;

async function getSettings() {
    const now = Date.now();
    if (cachedSettings && (now - cachedSettingsTime) < SETTINGS_CACHE_TTL_MS) return cachedSettings;
    await syncSettingsFromApp();
    const stored = await browser.storage.local.get(["monitoredExtensions", "excludedSites", "excludedAddresses", "enabled"]);
    cachedSettings = {
        monitoredExtensions: stored.monitoredExtensions ? new Set(stored.monitoredExtensions) : DEFAULT_MONITORED_EXTENSIONS,
        excludedSites: stored.excludedSites ?? DEFAULT_EXCLUDED_SITES,
        excludedAddresses: stored.excludedAddresses ?? DEFAULT_EXCLUDED_ADDRESSES,
        enabled: stored.enabled !== false,
    };
    cachedSettingsTime = now;
    return cachedSettings;
}

browser.storage.onChanged.addListener(() => {
    cachedSettings = null;
    cachedSettingsTime = 0;
});

async function syncSettingsFromApp() {
    try {
        const response = await new Promise((resolve, reject) => {
            browser.runtime.sendNativeMessage(NATIVE_HOST_ID, { type: "getSettings" }, (resp) => {
                if (browser.runtime.lastError) reject(new Error(browser.runtime.lastError.message));
                else resolve(resp);
            });
        });
        if (response?.type === "settings") {
            const update = {};
            if (Array.isArray(response.monitoredExtensions) && response.monitoredExtensions.length > 0)
                update.monitoredExtensions = response.monitoredExtensions;
            if (Array.isArray(response.excludedSites) && response.excludedSites.length > 0)
                update.excludedSites = response.excludedSites;
            if (Array.isArray(response.excludedAddresses) && response.excludedAddresses.length > 0)
                update.excludedAddresses = response.excludedAddresses;
            if (Object.keys(update).length > 0) {
                await browser.storage.local.set(update);
                cachedSettings = null;
            }
        }
    } catch (err) {
        console.info("[Stellar] Could not sync settings from app:", err.message);
    }
}

function wildcardToRegex(pattern) {
    const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
    return new RegExp("^" + escaped + "$", "i");
}

function matchesSitePattern(host, pattern) {
    return wildcardToRegex(pattern).test(host);
}

function matchesAddressPattern(url, pattern) {
    return wildcardToRegex(pattern).test(url);
}

function getUrlExtension(url) {
    try {
        const pathname = new URL(url).pathname;
        const lastSegment = pathname.split("/").pop().split("?")[0];
        const dotIdx = lastSegment.lastIndexOf(".");
        if (dotIdx >= 0) return lastSegment.slice(dotIdx + 1).toLowerCase();
    } catch {}
    return "";
}

function getUrlHost(url) {
    try { return new URL(url).hostname.toLowerCase(); }
    catch { return ""; }
}

async function shouldIntercept(url, mimeType, filenameHint) {
    if (!url || url.startsWith("data:") || url.startsWith("blob:")) return false;
    if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("ftp://")) return false;
    const settings = await getSettings();
    if (!settings.enabled) return false;
    const host = getUrlHost(url);
    for (const pattern of settings.excludedSites) if (matchesSitePattern(host, pattern)) return false;
    for (const pattern of settings.excludedAddresses) if (matchesAddressPattern(url, pattern)) return false;
    if (mimeType) {
        const PASS_THROUGH = ["text/html", "text/css", "application/javascript", "image/svg", "image/gif", "image/png", "image/jpeg", "image/webp"];
        if (PASS_THROUGH.some(t => mimeType.startsWith(t))) return false;
    }
    let ext = getUrlExtension(url);
    if (!ext && filenameHint) {
        const dotIdx = filenameHint.lastIndexOf(".");
        if (dotIdx >= 0) ext = filenameHint.slice(dotIdx + 1).toLowerCase().replace(/[^a-z0-9]/g, "");
    }
    if (ext) return settings.monitoredExtensions.has(ext);
    return false;
}

async function requestDownload(details) {
    return new Promise((resolve, reject) => {
        browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            type: "download",
            url: details.url,
            filename: details.filename ?? "",
            referrer: details.referrer ?? "",
            pageUrl: details.pageUrl ?? "",
            cookies: details.cookies ?? "",
            modifierKey: details.modifierKey ?? 0,
        }, (resp) => {
            if (browser.runtime.lastError) reject(new Error(browser.runtime.lastError.message));
            else resolve(resp);
        });
    });
}

async function ping() {
    try {
        const resp = await new Promise((resolve, reject) => {
            browser.runtime.sendNativeMessage(NATIVE_HOST_ID, { type: "ping" }, (r) => {
                if (browser.runtime.lastError) reject(new Error(browser.runtime.lastError.message));
                else resolve(r);
            });
        });
        return resp?.type === "ready";
    } catch {
        return false;
    }
}

async function refreshIcon() {
    const stored = await browser.storage.local.get(["enabled"]);
    const enabled = stored.enabled !== false;
    await browser.action.setIcon({ path: enabled ? ICONS_ENABLED : ICONS_DISABLED });
}

browser.downloads.onCreated.addListener(async (item) => {
    const modifierKey = getAndClearModifierKey();
    if (modifierKey > 0) return;
    if (!(await shouldIntercept(item.url, item.mime, item.filename))) return;
    await browser.downloads.cancel(item.id);
    await browser.downloads.erase({ id: item.id });
    const name = item.filename || "";
    let pageUrl = "";
    try {
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        if (tabs.length > 0) pageUrl = tabs[0].url || "";
    } catch {}
    await requestDownload({ url: item.url, filename: name, referrer: item.referrer || "", pageUrl, cookies: "", modifierKey: 0 });
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "recordModifierKey") {
        recordModifierKey(message.modifierKey);
        sendResponse({ ok: true });
        return true;
    }
    if (message.type === "getSettings") {
        (async () => {
            const stored = await browser.storage.local.get(["monitoredExtensions", "excludedSites", "excludedAddresses", "enabled"]);
            sendResponse({
                type: "settings",
                monitoredExtensions: stored.monitoredExtensions ?? [],
                excludedSites: stored.excludedSites ?? [],
                excludedAddresses: stored.excludedAddresses ?? [],
                enabled: stored.enabled !== false,
            });
        })();
        return true;
    }
    if (message.type === "ping") {
        (async () => {
            try {
                sendResponse({ alive: await ping() });
            } catch (err) {
                sendResponse({ alive: false, error: err?.message ?? "unknown" });
            }
        })();
        return true;
    }
    if (message.type === "setEnabled") {
        browser.storage.local.set({ enabled: !!message.value });
        cachedSettings = null;
        sendResponse({ ok: true });
        return true;
    }
});

browser.runtime.onInstalled.addListener(async () => {
    browser.contextMenus.create({ id: "stellar-download-link", title: "Download with Stellar", contexts: ["link"] });
    browser.contextMenus.create({ id: "stellar-download-media", title: "Download with Stellar", contexts: ["video", "audio", "image"] });
    await syncSettingsFromApp();
    await refreshIcon();
});

browser.runtime.onStartup.addListener(async () => {
    await syncSettingsFromApp();
    await refreshIcon();
});

browser.storage.onChanged.addListener(async () => {
    await refreshIcon();
});
