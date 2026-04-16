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
let liveSettings = {
    monitoredExtensions: DEFAULT_MONITORED_EXTENSIONS,
    excludedSites: DEFAULT_EXCLUDED_SITES,
    excludedAddresses: DEFAULT_EXCLUDED_ADDRESSES,
    enabled: true,
};

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

async function reloadLiveSettings() {
    const stored = await browser.storage.local.get(["monitoredExtensions", "excludedSites", "excludedAddresses", "enabled"]);
    liveSettings = {
        monitoredExtensions: stored.monitoredExtensions ? new Set(stored.monitoredExtensions) : DEFAULT_MONITORED_EXTENSIONS,
        excludedSites: stored.excludedSites ?? DEFAULT_EXCLUDED_SITES,
        excludedAddresses: stored.excludedAddresses ?? DEFAULT_EXCLUDED_ADDRESSES,
        enabled: stored.enabled !== false,
    };
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
            // Allow empty arrays — the user may have cleared all entries in the app.
            if (Array.isArray(response.monitoredExtensions))
                update.monitoredExtensions = response.monitoredExtensions;
            if (Array.isArray(response.excludedSites))
                update.excludedSites = response.excludedSites;
            if (Array.isArray(response.excludedAddresses))
                update.excludedAddresses = response.excludedAddresses;
            if (Object.keys(update).length > 0) {
                await browser.storage.local.set(update);
                cachedSettings = null;
            }
        }
    } catch (err) {
        console.info("[Stellar] Could not sync settings from app:", err.message);
    } finally {
        await reloadLiveSettings();
    }
}

function wildcardToRegex(pattern) {
    const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
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

function hasExplicitDownloadIntent(url) {
    try {
        const u = new URL(url);
        const path = u.pathname.toLowerCase();
        const dlValue = (u.searchParams.get("dl") || "").toLowerCase();
        const dlIntent = dlValue === "1" || dlValue === "true" || dlValue === "yes" || dlValue === "download";
        return path.includes("/download/")
            || u.searchParams.has("download")
            || dlIntent
            || u.searchParams.has("attachment")
            || u.searchParams.has("filename")
            || u.searchParams.has("response-content-disposition")
            || u.searchParams.get("export") === "download"
            || u.searchParams.get("alt") === "media";
    } catch {
        return false;
    }
}

function isApiRpcRequest(url, filenameHint = "", mimeType = "") {
    try {
        const u = new URL(url);
        const host = u.hostname.toLowerCase();
        const path = u.pathname.toLowerCase();
        const dlValue = (u.searchParams.get("dl") || "").toLowerCase();
        const dlIntent = dlValue === "1" || dlValue === "true" || dlValue === "yes" || dlValue === "download";
        const fn = String(filenameHint || "").toLowerCase();
        const mt = String(mimeType || "").toLowerCase();
        const hasPathExt = /\/[^/?#]+\.[a-z0-9]{1,8}$/i.test(path);
        const apiPath = /(?:^|\/)(api|graphql|rpc|ajax|batchexecute)(?:\/|$)/i.test(path)
            || path.includes("/_/");
        const explicitDownload = path.includes("/download/")
            || u.searchParams.has("download")
            || dlIntent
            || u.searchParams.has("attachment")
            || u.searchParams.has("filename")
            || u.searchParams.has("response-content-disposition")
            || u.searchParams.get("alt") === "media"
            || u.searchParams.get("export") === "download";

        // Analytics/telemetry beacons should never be treated as downloads.
        if ((path.endsWith("/td") || path.includes("/td/"))
            && (u.searchParams.has("gtm") || /^gtm-/i.test(String(u.searchParams.get("id") || "")))) {
            return true;
        }

        if (apiPath && !explicitDownload
            && (!hasPathExt || fn === "response.bin" || fn === "response"
                || mt.startsWith("application/json") || mt.startsWith("text/plain")
                || mt.startsWith("text/javascript"))) {
            return true;
        }
        // YouTube webapp static asset buckets (not user downloads).
        if ((host === "youtube.com" || host.endsWith(".youtube.com"))
            && (path.startsWith("/s/") || path.startsWith("/yts/"))) {
            return true;
        }
        if ((host === "gemini.google.com" || host.endsWith(".google.com"))
            && path.includes("/data/batchexecute")) {
            return true;
        }
        if (u.searchParams.has("rpcids") && u.searchParams.get("rt") === "c")
            return true;
        if ((fn === "response.bin" || fn === "response")
            && (path.includes("/api/") || mt.startsWith("application/json")
                || mt.startsWith("text/plain") || mt.startsWith("text/javascript"))) {
            return true;
        }
    } catch {}
    return false;
}

function forceIntercept(url) {
    try {
        const u = new URL(url);
        const host = u.hostname.toLowerCase();
        const path = u.pathname.toLowerCase();
        const isDriveUserContent = host === "drive.usercontent.google.com"
            || host.endsWith(".drive.usercontent.google.com");
        const isGoogleDocHost = host === "drive.google.com"
            || host.endsWith(".drive.google.com")
            || host === "docs.google.com"
            || host.endsWith(".docs.google.com");
        if (!isDriveUserContent && !isGoogleDocHost) return false;
        // Only intercept URLs that carry explicit download signals — auth/warmup
        // endpoints on these hosts (e.g. /auth_warmupv) must not be captured.
        if (path === "/uc" || path.startsWith("/download") || path.includes("/download/")) return true;
        if (u.searchParams.get("export") === "download") return true;
        if (u.searchParams.has("response-content-disposition")) return true;
        if (isDriveUserContent && u.searchParams.has("id")) return true;
        return false;
    } catch { return false; }
}

function shouldInterceptSync(url, mimeType, filenameHint, explicitIntent = false) {
    if (!url || url.startsWith("data:") || url.startsWith("blob:")) return false;
    if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("ftp://")) return false;
    if (isApiRpcRequest(url, filenameHint, mimeType)) return false;
    if (!liveSettings.enabled) return false;
    const host = getUrlHost(url);
    for (const pattern of liveSettings.excludedSites) if (matchesSitePattern(host, pattern)) return false;
    for (const pattern of liveSettings.excludedAddresses) if (matchesAddressPattern(url, pattern)) return false;
    if (mimeType) {
        const PASS_THROUGH = ["text/html", "text/css", "application/javascript", "image/svg", "image/gif", "image/png", "image/jpeg", "image/webp"];
        if (PASS_THROUGH.some(t => mimeType.startsWith(t))) return false;
    }
    let ext = getUrlExtension(url);
    if (!ext && filenameHint) {
        const dotIdx = filenameHint.lastIndexOf(".");
        if (dotIdx >= 0) ext = filenameHint.slice(dotIdx + 1).toLowerCase().replace(/[^a-z0-9]/g, "");
    }
    const MEDIA_EXTS = new Set([
        "mp3","m4a","aac","ogg","wav","wma","flac","aif","ra",
        "mp4","m4v","mkv","avi","mov","wmv","webm","mpeg","mpg","3gp","ogv","rm","rmvb","asf","qt"
    ]);
    const explicitDownload = hasExplicitDownloadIntent(url) || explicitIntent;
    if (ext) {
        if (MEDIA_EXTS.has(ext) && !explicitDownload)
            return false;
        return liveSettings.monitoredExtensions.has(ext);
    }
    // Explicit user-initiated download clicks (e.g. blob-resolved signed URLs
    // without a file extension) should still be captured by Stellar.
    if (explicitDownload) return true;
    return false;
}

async function shouldIntercept(url, mimeType, filenameHint, explicitIntent = false) {
    if (!url || url.startsWith("data:") || url.startsWith("blob:")) return false;
    if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("ftp://")) return false;
    if (isApiRpcRequest(url, filenameHint, mimeType)) return false;
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
    const MEDIA_EXTS = new Set([
        "mp3","m4a","aac","ogg","wav","wma","flac","aif","ra",
        "mp4","m4v","mkv","avi","mov","wmv","webm","mpeg","mpg","3gp","ogv","rm","rmvb","asf","qt"
    ]);
    const explicitDownload = hasExplicitDownloadIntent(url) || explicitIntent;
    if (ext) {
        if (MEDIA_EXTS.has(ext) && !explicitDownload)
            return false;
        return settings.monitoredExtensions.has(ext);
    }
    // Explicit user-initiated download clicks (e.g. blob-resolved signed URLs
    // without a file extension) should still be captured by Stellar.
    if (explicitDownload) return true;
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

function getHeaderValue(headers, name) {
    const wanted = name.toLowerCase();
    for (const h of headers || []) {
        if ((h.name || "").toLowerCase() === wanted) return h.value || "";
    }
    return "";
}

function getFilenameFromContentDisposition(contentDisposition) {
    if (!contentDisposition) return "";
    const utf8Match = contentDisposition.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
    if (utf8Match && utf8Match[1]) {
        try { return decodeURIComponent(utf8Match[1].replace(/^"|"$/g, "")); } catch {}
    }
    const basicMatch = contentDisposition.match(/filename\s*=\s*("?)([^";]+)\1/i);
    if (basicMatch && basicMatch[2]) return basicMatch[2];
    return "";
}

browser.webRequest.onHeadersReceived.addListener(
    (details) => {
        // Only intercept navigation-type requests. Page-internal fetches (XHR/fetch),
        // beacons, pings, websockets, and CSP reports are never user-initiated downloads.
        const NON_DOWNLOAD_TYPES = new Set(["xmlhttprequest","beacon","ping","csp_report","websocket"]);
        if (NON_DOWNLOAD_TYPES.has(details.type)) return {};

        const modifierKey = getAndClearModifierKey();
        if (modifierKey > 0) return {};

        const contentType = getHeaderValue(details.responseHeaders, "content-type").toLowerCase();
        const contentDisposition = getHeaderValue(details.responseHeaders, "content-disposition");
        const filenameHint = getFilenameFromContentDisposition(contentDisposition);
        // Content-Disposition: attachment means the server explicitly wants this saved as a file.
        // Treat it as explicit download intent regardless of URL structure.
        const isAttachment = /^\s*attachment/i.test(contentDisposition);

        if (!forceIntercept(details.url) && !shouldInterceptSync(details.url, contentType, filenameHint, isAttachment)) return {};

        const pageUrl = details.documentUrl || details.originUrl || "";
        const referrer = details.originUrl || details.documentUrl || "";

        const capturedUrl = details.url;
        const capturedFilename = filenameHint;
        const capturedReferrer = referrer;
        const capturedPageUrl = pageUrl;
        setTimeout(async () => {
            let cookieHeader = "";
            try {
                const urlObj = new URL(capturedUrl);
                const cookieUrls = [capturedUrl];
                // Also collect from parent domains so auth cookies (e.g. on .google.com)
                // are included when the download host is a subdomain like drive.usercontent.google.com.
                const parts = urlObj.hostname.split(".");
                for (let i = 1; i < parts.length - 1; i++)
                    cookieUrls.push(`${urlObj.protocol}//${parts.slice(i).join(".")}/`);
                const seen = new Set();
                const allCookies = [];
                for (const cu of cookieUrls) {
                    const batch = await browser.cookies.getAll({ url: cu });
                    for (const c of batch) {
                        if (!seen.has(c.name)) { seen.add(c.name); allCookies.push(c); }
                    }
                }
                cookieHeader = allCookies.map(c => `${c.name}=${c.value}`).join("; ");
            } catch (err) {
                console.warn("[Stellar] Could not collect cookies for intercepted download:", err);
            }
            requestDownload({
                url: capturedUrl,
                filename: capturedFilename,
                referrer: capturedReferrer,
                pageUrl: capturedPageUrl,
                cookies: cookieHeader,
                modifierKey: 0,
            }).catch((err) => {
                console.error("[Stellar] Failed to send download to native host:", err);
            });
        }, 0);

        return { cancel: true };
    },
    { urls: ["<all_urls>"] },
    ["blocking", "responseHeaders"]
);

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

    if (message.type === "interceptLinkClick") {
        (async () => {
            try {
                const url = message.url || "";
                const filename = message.filename || "";
                const explicitIntent = !!message.explicitIntent;
                const allowed = forceIntercept(url) || await shouldIntercept(url, "", filename, explicitIntent);
                if (!allowed) {
                    sendResponse({ ok: false, reason: "not-intercepted" });
                    return;
                }
                // Collect cookies in the background so authenticated API endpoints
                // (e.g. blob-resolved download URLs requiring session tokens) work.
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
                            const batch = await browser.cookies.getAll({ url: cu });
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

browser.runtime.onInstalled.addListener(async () => {
    browser.contextMenus.create({ id: "stellar-download-link", title: "Download with Stellar", contexts: ["link"] });
    browser.contextMenus.create({ id: "stellar-download-media", title: "Download with Stellar", contexts: ["video", "audio", "image"] });
    await syncSettingsFromApp();
    await refreshIcon();
});

browser.contextMenus.onClicked.addListener(async (info) => {
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
            const batch = await browser.cookies.getAll({ url: cu });
            for (const c of batch) {
                if (!seen.has(c.name)) { seen.add(c.name); allCookies.push(c); }
            }
        }
        cookieHeader = allCookies.map(c => `${c.name}=${c.value}`).join("; ");
    } catch {}
    try {
        await requestDownload({
            url,
            filename: "",
            referrer: info.frameUrl ?? info.pageUrl ?? "",
            pageUrl: info.pageUrl ?? "",
            cookies: cookieHeader,
            modifierKey: 0,
        });
    } catch (err) {
        console.error("[Stellar] Context menu download failed:", err);
    }
});

browser.runtime.onStartup.addListener(async () => {
    await syncSettingsFromApp();
    await refreshIcon();
});

browser.storage.onChanged.addListener(async () => {
    await reloadLiveSettings();
    await refreshIcon();
});

reloadLiveSettings().catch(() => {});
