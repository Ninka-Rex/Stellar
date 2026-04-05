// Stellar Download Manager — Firefox Extension
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

"use strict";

const NATIVE_HOST_ID = "com.stellar.downloadmanager";

// ── Default lists (kept in sync with AppSettings defaults) ───────────────────

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

const DEFAULT_EXCLUDED_ADDRESSES = [
    "http://*.appspot.com/*/*mp3",
    "http://*.akamaihd.net/*.mp3",
    "http://*.akamaihd.net/*/*.zip",
    "http://*.appspot.com/*/audio/*.mp3",
    "http://*.browser.ovi.com/*/*sounds/*",
    "http://*.ask.com/*toolbar/*config*.zip",
    "http://*.cloudfront.net/game/*/res/*.bin",
    "http://*.download.windowsupdate.com/*",
    "http://*.cjn.com/*.gif",
    "http://*.ak.fbcdn.net/*.mp3",
    "http://*.farmville.com/*.mp3",
    "http://*.teletalk.com.bd/admitcard/card.php",
    "http://*.zynga.com/*.mp3",
    "http://*.vkontakte.ru/*.mp3",
    "http://8r6maar.qaplaany.net/*/*.mp3",
    "http://*.edubiz-info.com/file/*upload/*",
    "http://ad.*.yieldmanager.com/*",
    "http://*.vk.com/*.zip",
    "https://www.google.com/voice/address*",
    "http://ad.yieldmanager.com/*",
    "http://ak.imgfarm.com/images/download/spokesperson/html5/audio/*.mp3",
    "http://api.browser.ovi.ru/config/all_api*.zip",
    "http://assets.*.zynga.com/*.zip",
    "http://c.cdn.ask.com/images/*.bin",
    "http://cdndownload.adobe.com/firefox/*primetime*.zip",
    "http://cdn.engine.pu/*.pdf",
    "http://cs.soundboy.openh264.org/*.zip",
    "http://counters.gigya.com/Wildfire/counters/*=*.tif",
    "http://dar.youknowbest.com/Resources/*.img",
    "http://get.opera.com/pub/opera/autoupdate/*.exe",
    "http://get.opera.com/pub/opera/autoupdate/*.msi",
    "http://get.geo.opera.com/services/files/*.zip",
    "http://img.mail.126.net/*",
    "http://img2.mail.126.net/*",
    "http://images.apple.com/*/*/*/*",
    "http://img.imgsmail.ru/*/message.bin",
    "http://img.imgsmail.ru/*/*.mp3",
    "http://imimg.proxy.aol.com/*",
    "http://mail.yimg.com/us.yimg.com/*",
    "http://mq1.yimg.com/*",
    "http://img.ttd.eu.delivery.mp.microsoft.com/filestreamingservice/files/*",
    "http://imgfarm.com/images/*/*.mp3",
    "http://msedge.b.tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/*",
    "http://o.aolcdn.com/cdn.webmail.aol.com/*/aol/*/sounds/*.mp3",
    "http://quickaccess-d.micron.com/quickaccess_*.dat*",
    "http://static.ak.fbcdn.net/*.mp3",
    "http://statics.verycd.com/js/sounds/*.mp3",
    "http://toolbar.live.com/static/js/sm/*",
    "http://village.*.amazonaws.com/static/sound/*.mp3",
    "http://widget*.meebo.com/*.mp3",
    "http://www.6rb.com/*.ram",
    "http://www.8rtab.com/library/resources/*.ram",
    "http://www.cbox.ws/box/click*.wav",
    "http://www.download.windowsupdate.com/*",
    "http://www.smilebrowser.com/release/*.console.exe",
    "http://www.sonyericsson.com/origin/images/content/*.exe",
    "http://www.nancies.org/audio/files/*.mp3",
    "http://cloudflare.com/*",
    "http://gvt1.com/edgedl/widevine-cdm/*.zip",
    "https://*.meebo.com/*/skin/sound/*.mp3",
    "https://*.myspacecdn.com/modules/weben/static/audio/*.mp3",
    "https://akamaihd.net/*",
    "https://ak.imgfarm.com/images/download/spokesperson/html5/audio/*.mp3",
    "https://appspot.com/*/audio/*.mp3",
    "https://cdndownload.adobe.com/firefox/*primetime*.zip",
    "https://cdn.thegameawards.com/frontend/video/tga*.mp4",
    "https://complex.overleaf.com/project/*/output/output.pdf*",
    "https://download.sophos.com/tools/SophosScanAndClean_x64.exe",
    "https://fcdownload.macromedia.com/get/*.z",
    "https://g.symcd.com/common/sounds/interval.mp3",
    "https://img.wonderhowto.com/img/Iotaionstring_7.mp4",
    "https://pc.vue.cn/comn/v1/study-login/asset/*.mp3",
    "https://lookaside.fbsbx.com/file/*",
    "https://redirector.gvt1.com/edgedl/widevine-cdm/*.zip",
    "https://s3.download.com/Documents/2597422/harvard-docs.pdf",
    "https://sso-t-orange.fr/om/l/facture/1.0.pdf*",
    "https://swx.cdn.skype.com/assets/*/audio/*",
    "https://web.whatsapp.com/img/*",
    "https://www.bing.com/images/search?q=images/AutoApply*.mp4",
    "https://www.sysiad.net/hosifre/software_count.php",
    "https://www.youtube.com/search/audio/*.mp3"
];

// ── Cookie retrieval ──────────────────────────────────────────────────────────
// The service worker is non-persistent — it can be killed between the webRequest
// firing and downloads.onCreated. We therefore fetch cookies ON DEMAND when
// the download is intercepted, using the active tab's cookieStoreId so we
// correctly handle Firefox Multi-Account Containers.

async function getCookiesForUrl(url) {
    // Build list of URLs to query: the download URL plus all parent domains,
    // so that .google.com auth cookies are included.
    let cookieUrls;
    try {
        const urlObj = new URL(url);
        cookieUrls = [url];
        const parts = urlObj.hostname.split(".");
        for (let i = 1; i < parts.length - 1; i++)
            cookieUrls.push(`${urlObj.protocol}//${parts.slice(i).join(".")}/`);
    } catch { return ""; }

    // Collect candidate storeIds: active tabs first (catches containers), then
    // fall back to every known store, then finally the bare default.
    const storeIds = [];
    try {
        const tabs = await browser.tabs.query({ active: true });
        for (const t of tabs)
            if (t.cookieStoreId && !storeIds.includes(t.cookieStoreId))
                storeIds.push(t.cookieStoreId);
    } catch { /* ignore */ }
    try {
        const stores = await browser.cookies.getAllCookieStores();
        for (const s of stores)
            if (!storeIds.includes(s.id)) storeIds.push(s.id);
    } catch { /* ignore */ }
    if (!storeIds.length) storeIds.push("firefox-default");

    const seen = new Set();
    const allCookies = [];
    for (const storeId of storeIds) {
        for (const cu of cookieUrls) {
            try {
                const batch = await browser.cookies.getAll({ url: cu, storeId });
                for (const c of batch)
                    if (!seen.has(c.name)) { seen.add(c.name); allCookies.push(c); }
            } catch { /* store may not exist */ }
        }
        // Stop as soon as we found actual auth cookies — the right container was found
        if (allCookies.some(c => c.name === "SID" || c.name === "__Secure-1PSID" || c.name === "SSID"))
            break;
    }
    return allCookies.map(c => `${c.name}=${c.value}`).join("; ");
}

// ── Re-entrancy guard ─────────────────────────────────────────────────────────
// Tracks URLs currently being handed off to Stellar so that the new tab opened
// by a fallback (or any re-triggered download event) doesn't cause a loop.
const pendingUrls = new Set();

// ── Settings cache ────────────────────────────────────────────────────────────
// Two-level caching:
//  1. In-memory (cachedSettings): fast path, valid for SETTINGS_CACHE_TTL_MS.
//     Cleared when the service worker restarts, ensuring each new activation
//     fetches a fresh copy from the app.
//  2. browser.storage.local: persistent fallback used when the app is not running.
//
// On every download decision we re-sync from the app if the TTL has expired.
// The native host reads QSettings directly (no IPC), so it reflects changes
// saved by the app immediately — no restart of Stellar required.

const SETTINGS_CACHE_TTL_MS = 5000; // 5 seconds — avoids a process spawn per download in bursts
let cachedSettings = null;
let cachedSettingsTime = 0;

async function getSettings() {
    const now = Date.now();
    if (cachedSettings && (now - cachedSettingsTime) < SETTINGS_CACHE_TTL_MS) {
        return cachedSettings;
    }
    // TTL expired (or first call in this service-worker activation): sync from app.
    await syncSettingsFromApp();
    // Read the (just-updated) persistent store.
    const stored = await browser.storage.local.get([
        "monitoredExtensions",
        "excludedSites",
        "excludedAddresses",
        "enabled"
    ]);
    cachedSettings = {
        monitoredExtensions: stored.monitoredExtensions
            ? new Set(stored.monitoredExtensions)
            : DEFAULT_MONITORED_EXTENSIONS,
        excludedSites:    stored.excludedSites    ?? DEFAULT_EXCLUDED_SITES,
        excludedAddresses: stored.excludedAddresses ?? DEFAULT_EXCLUDED_ADDRESSES,
        enabled: stored.enabled !== false
    };
    cachedSettingsTime = now;
    return cachedSettings;
}

// Invalidate in-memory cache on storage changes (e.g. popup edits)
browser.storage.onChanged.addListener(() => {
    cachedSettings = null;
    cachedSettingsTime = 0;
});

/**
 * Fetch current settings from the running Stellar app and persist them to
 * browser.storage.local so the extension uses up-to-date filter lists.
 * Called on install and every time the service worker starts.
 */
async function syncSettingsFromApp() {
    try {
        const response = await new Promise((resolve, reject) => {
            browser.runtime.sendNativeMessage(NATIVE_HOST_ID, { type: "getSettings" }, (resp) => {
                if (browser.runtime.lastError)
                    reject(new Error(browser.runtime.lastError.message));
                else
                    resolve(resp);
            });
        });
        if (response?.type === "settings") {
            // Only update fields that the app returned non-empty values for, so that
            // an app that is not yet running doesn't wipe the user's stored settings.
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
        // App not running — keep using whatever is stored locally.
        console.info("[Stellar] Could not sync settings from app (app may not be running):", err.message);
    }
}

// Sync settings every time the service worker wakes up
browser.runtime.onStartup.addListener(syncSettingsFromApp);

// ── Pattern matching ──────────────────────────────────────────────────────────

/**
 * Convert a wildcard pattern (with *) to a RegExp.
 * The pattern may match anywhere in the string unless anchored.
 */
function wildcardToRegex(pattern) {
    const escaped = pattern
        .replace(/[.+^${}()|[\]\\]/g, "\\$&")  // escape regex specials except *
        .replace(/\*/g, ".*");                   // * → .*
    return new RegExp("^" + escaped + "$", "i");
}

/**
 * Check if a hostname matches a site pattern like *.update.microsoft.com
 */
function matchesSitePattern(host, pattern) {
    return wildcardToRegex(pattern).test(host);
}

/**
 * Check if a full URL matches a URL address pattern.
 * Patterns use * as a wildcard, matched against the full URL string.
 */
function matchesAddressPattern(url, pattern) {
    return wildcardToRegex(pattern).test(url);
}

/**
 * Extract the file extension from a URL (without dot, lowercase).
 */
function getUrlExtension(url) {
    try {
        const pathname = new URL(url).pathname;
        const lastSegment = pathname.split("/").pop().split("?")[0];
        const dotIdx = lastSegment.lastIndexOf(".");
        if (dotIdx >= 0) return lastSegment.slice(dotIdx + 1).toLowerCase();
    } catch { /* ignore */ }
    return "";
}

/**
 * Extract the hostname from a URL.
 */
function getUrlHost(url) {
    try { return new URL(url).hostname.toLowerCase(); }
    catch { return ""; }
}

/**
 * Extract the best filename from a URL + optional Content-Disposition header.
 */
function extractFilename(url, contentDisposition) {
    if (contentDisposition) {
        // RFC 5987 encoded: filename*=UTF-8''...
        const rfcMatch = contentDisposition.match(/filename\*\s*=\s*UTF-8''([^;\n]+)/i);
        if (rfcMatch) return decodeURIComponent(rfcMatch[1].trim());
        // Plain: filename="..." or filename=...
        const plainMatch = contentDisposition.match(/filename\s*=\s*["']?([^"';\n]+)/i);
        if (plainMatch) return plainMatch[1].trim().replace(/['"]/g, "");
    }
    try {
        const pathname = new URL(url).pathname;
        const name = decodeURIComponent(pathname.split("/").pop().split("?")[0]);
        if (name) return name;
    } catch { /* ignore */ }
    return "download";
}

// ── Core interception logic ───────────────────────────────────────────────────

/**
 * Decide whether Stellar should intercept this download.
 * @param {string} url
 * @param {string|null} mimeType
 * @param {string} [filenameHint]  - filename from the download item (may have extension even if URL doesn't)
 */
async function shouldIntercept(url, mimeType, filenameHint) {
    // Skip non-http schemes
    if (!url || (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("ftp://")))
        return false;
    // Skip data: and blob: URIs
    if (url.startsWith("data:") || url.startsWith("blob:"))
        return false;

    const settings = await getSettings();

    // Global enable/disable
    if (!settings.enabled) return false;

    const host = getUrlHost(url);

    // Check excluded sites
    for (const pattern of settings.excludedSites) {
        if (matchesSitePattern(host, pattern)) return false;
    }

    // Check excluded address patterns
    for (const pattern of settings.excludedAddresses) {
        if (matchesAddressPattern(url, pattern)) return false;
    }

    // Check if mime type is a pass-through type (e.g. HTML pages, CSS, JS, images served inline)
    if (mimeType) {
        const PASS_THROUGH = ["text/html", "text/css", "application/javascript", "image/svg", "image/gif", "image/png", "image/jpeg", "image/webp"];
        if (PASS_THROUGH.some(t => mimeType.startsWith(t))) return false;
    }

    // Determine the best file extension we can: URL path first, then filename hint.
    let ext = getUrlExtension(url);
    if (!ext && filenameHint) {
        const dotIdx = filenameHint.lastIndexOf(".");
        if (dotIdx >= 0) ext = filenameHint.slice(dotIdx + 1).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    // If we have a known extension: intercept only if it's in the monitored list.
    if (ext) return settings.monitoredExtensions.has(ext);

    // No extension info at all — fall back to MIME type.
    // Map specific MIME types to their canonical extension and check the monitored list.
    // This ensures e.g. "video/mp4" is only intercepted if "mp4" is monitored.
    if (mimeType) {
        const MIME_TO_EXT = {
            "application/pdf":              "pdf",
            "application/zip":              "zip",
            "application/x-zip":            "zip",
            "application/x-zip-compressed": "zip",
            "application/x-rar-compressed": "rar",
            "application/x-rar":            "rar",
            "application/vnd.rar":          "rar",
            "application/x-7z-compressed":  "7z",
            "application/x-7z":             "7z",
            "application/x-tar":            "tar",
            "application/x-gzip":           "gz",
            "application/gzip":             "gz",
            "application/x-bzip2":          "bz2",
            "application/x-xz":             "xz",
            "application/x-msdownload":     "exe",
            "application/x-msi":            "msi",
            "video/mp4":                    "mp4",
            "video/x-matroska":             "mkv",
            "video/x-msvideo":              "avi",
            "video/quicktime":              "mov",
            "video/x-ms-wmv":               "wmv",
            "video/webm":                   "webm",
            "audio/mpeg":                   "mp3",
            "audio/mp4":                    "m4a",
            "audio/ogg":                    "ogg",
            "audio/wav":                    "wav",
            "audio/x-ms-wma":               "wma",
            "audio/aac":                    "aac",
            "audio/flac":                   "flac",
            "image/tiff":                   "tif",
        };
        for (const [mime, mappedExt] of Object.entries(MIME_TO_EXT)) {
            if (mimeType === mime || mimeType.startsWith(mime + ";")) {
                return settings.monitoredExtensions.has(mappedExt);
            }
        }
        // For generic video/* and audio/* catch-alls not in the table above,
        // intercept only if the user has any video/audio extensions monitored.
        if (mimeType.startsWith("video/")) {
            const VIDEO_EXTS = ["mp4","mkv","avi","mov","wmv","flv","webm","m4v","mpg","mpeg","3gp","ogv","rm","rmvb","asf","qt"];
            return VIDEO_EXTS.some(e => settings.monitoredExtensions.has(e));
        }
        if (mimeType.startsWith("audio/")) {
            const AUDIO_EXTS = ["mp3","aac","wav","flac","ogg","m4a","wma","ra","aif","mpa"];
            return AUDIO_EXTS.some(e => settings.monitoredExtensions.has(e));
        }
        // application/octet-stream and other generic binary types: we have no
        // reliable way to determine the file type, so do NOT intercept.
        // The user can always right-click → "Download with Stellar" for these.
    }

    return false;
}

/**
 * Send a download request to the Stellar native messaging host.
 */
function sendToStellar(details) {
    return new Promise((resolve, reject) => {
        browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            type:     "download",
            url:      details.url,
            filename: details.filename ?? "",
            referrer: details.referrer ?? "",
            cookies:  details.cookies  ?? ""
        }, (response) => {
            if (browser.runtime.lastError) {
                reject(new Error(browser.runtime.lastError.message));
            } else {
                resolve(response);
            }
        });
    });
}

// Domains that serve direct file downloads without a file extension in the URL.
// Always intercept these regardless of extension/MIME type.
const FORCE_INTERCEPT_HOSTS = [
    "drive.usercontent.google.com",
    "drive.google.com",
    "docs.google.com",
];

function forceIntercept(url) {
    try {
        const host = new URL(url).hostname.toLowerCase();
        return FORCE_INTERCEPT_HOSTS.some(h => host === h || host.endsWith("." + h));
    } catch { return false; }
}

/**
 * Handle a download item created by Firefox.
 */
async function handleDownloadCreated(downloadItem) {
    const { url, filename, referrer, mime, id } = downloadItem;

    // Skip URLs already being processed — prevents infinite loops if something
    // re-triggers a download event for the same URL.
    if (pendingUrls.has(url)) return;
    if (!forceIntercept(url) && !(await shouldIntercept(url, mime, filename))) return;

    pendingUrls.add(url);

    // Cancel the browser-managed download immediately
    try { await browser.downloads.cancel(id); } catch { /* already gone */ }
    try { await browser.downloads.erase({ id }); }   catch { /* ignore */ }

    const name = filename || extractFilename(url, null);

    const cookieHeader = await getCookiesForUrl(url);

    try {
        await sendToStellar({ url, filename: name, referrer: referrer ?? "", cookies: cookieHeader });
    } catch (err) {
        // Native host unreachable — do NOT open a new tab (that re-triggers
        // downloads.onCreated and causes an infinite loop). Just log it.
        console.error("[Stellar] Failed to route download to Stellar:", err.message);
    } finally {
        pendingUrls.delete(url);
    }
}

// ── Event listeners ───────────────────────────────────────────────────────────

browser.downloads.onCreated.addListener(handleDownloadCreated);

browser.runtime.onInstalled.addListener(async (details) => {
    // On first install, write defaults to storage so the popup can read them
    if (details.reason === "install") {
        await browser.storage.local.set({
            monitoredExtensions: [...DEFAULT_MONITORED_EXTENSIONS],
            excludedSites:       DEFAULT_EXCLUDED_SITES,
            excludedAddresses:   DEFAULT_EXCLUDED_ADDRESSES,
            enabled:             true
        });
    }

    // Sync settings from the app so the extension uses the user's configured lists
    await syncSettingsFromApp();

    // Register right-click context menu
    browser.contextMenus.create({
        id:       "stellar-download-link",
        title:    "Download with Stellar",
        contexts: ["link", "image", "video", "audio"]
    });
});

browser.contextMenus.onClicked.addListener(async (info) => {
    const url = info.linkUrl || info.srcUrl;
    if (!url) return;

    const cookieHeader = await getCookiesForUrl(url);

    try {
        await sendToStellar({
            url,
            filename: extractFilename(url, null),
            referrer: info.pageUrl ?? "",
            cookies:  cookieHeader
        });
    } catch (err) {
        console.error("[Stellar] Context-menu download failed:", err.message);
    }
});

// ── Messages from the popup ───────────────────────────────────────────────────

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type === "ping") {
        // Try pinging the native host
        browser.runtime.sendNativeMessage(NATIVE_HOST_ID, { type: "ping" }, (response) => {
            if (browser.runtime.lastError) {
                sendResponse({ alive: false, error: browser.runtime.lastError.message });
            } else {
                sendResponse({ alive: response?.type === "ready" });
            }
        });
        return true; // keep message channel open for async response
    }

    if (message.type === "getSettings") {
        getSettings().then(s => {
            sendResponse({
                monitoredExtensions: [...s.monitoredExtensions],
                excludedSites:       s.excludedSites,
                excludedAddresses:   s.excludedAddresses,
                enabled:             s.enabled
            });
        });
        return true;
    }

    if (message.type === "setEnabled") {
        browser.storage.local.set({ enabled: !!message.value });
        cachedSettings = null;
        sendResponse({ ok: true });
        return false;
    }

    if (message.type === "focus") {
        browser.runtime.sendNativeMessage(NATIVE_HOST_ID, { type: "focus" }, () => {});
        sendResponse({ ok: true });
        return false;
    }
});
