// Stellar Download Manager — Shared Messaging Utilities
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

// extensions/shared/messaging.js
// Shared utilities for communicating with the Stellar native host.
// Used by both Chrome MV3 and Firefox MV3 service workers.

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

// ── Settings cache ────────────────────────────────────────────────────────────
// Two-level caching: in-memory with a 5-second TTL, backed by chrome.storage.local.
// On each download decision the TTL is checked; if expired, fresh settings are
// fetched from the app (native host reads QSettings directly, always current).

const SETTINGS_CACHE_TTL_MS = 5000;
let cachedSettings = null;
let cachedSettingsTime = 0;

async function getSettings() {
    const now = Date.now();
    if (cachedSettings && (now - cachedSettingsTime) < SETTINGS_CACHE_TTL_MS) {
        return cachedSettings;
    }
    await syncSettingsFromApp();
    const stored = await chrome.storage.local.get([
        "monitoredExtensions",
        "excludedSites",
        "excludedAddresses",
        "enabled"
    ]);
    cachedSettings = {
        monitoredExtensions: stored.monitoredExtensions
            ? new Set(stored.monitoredExtensions)
            : DEFAULT_MONITORED_EXTENSIONS,
        excludedSites:      stored.excludedSites      ?? DEFAULT_EXCLUDED_SITES,
        excludedAddresses:  stored.excludedAddresses  ?? [],
        enabled:            stored.enabled !== false
    };
    cachedSettingsTime = now;
    return cachedSettings;
}

// Invalidate in-memory cache on storage changes
chrome.storage.onChanged.addListener(() => {
    cachedSettings = null;
    cachedSettingsTime = 0;
});

/**
 * Fetch current settings from the running Stellar app and persist them to
 * chrome.storage.local so the extension uses up-to-date filter lists.
 */
export async function syncSettingsFromApp() {
    try {
        const response = await sendMessage({ type: "getSettings" });
        if (response?.type === "settings") {
            const update = {};
            if (Array.isArray(response.monitoredExtensions) && response.monitoredExtensions.length > 0)
                update.monitoredExtensions = response.monitoredExtensions;
            if (Array.isArray(response.excludedSites) && response.excludedSites.length > 0)
                update.excludedSites = response.excludedSites;
            if (Array.isArray(response.excludedAddresses) && response.excludedAddresses.length > 0)
                update.excludedAddresses = response.excludedAddresses;
            if (Object.keys(update).length > 0) {
                await chrome.storage.local.set(update);
                cachedSettings = null;
            }
        }
    } catch (err) {
        console.info("[Stellar] Could not sync settings from app (app may not be running):", err.message);
    }
}

// ── Pattern matching ──────────────────────────────────────────────────────────

function wildcardToRegex(pattern) {
    const escaped = pattern
        .replace(/[.+^${}()|[\]\\]/g, "\\$&")
        .replace(/\*/g, ".*");
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
    } catch { /* ignore */ }
    return "";
}

function getUrlHost(url) {
    try { return new URL(url).hostname.toLowerCase(); }
    catch { return ""; }
}

// ── isApiRpcRequest ───────────────────────────────────────────────────────────

/**
 * Returns true if the URL looks like an internal API/RPC call rather than a
 * user-initiated file download. Used to avoid intercepting page-internal XHR
 * traffic that the downloads.onCreated path might surface.
 */
function isApiRpcRequest(url, filenameHint = "", mimeType = "") {
    try {
        const u = new URL(url);
        const path = u.pathname.toLowerCase();
        const fn = String(filenameHint || "").toLowerCase();
        const mt = String(mimeType || "").toLowerCase();

        // If the URL path ends with a real file extension it is a file download,
        // even if the path also contains /api/ segments (e.g. /api/files/doc.pdf).
        const pathExtMatch = /\.([a-z0-9]{1,10})(?:[?#]|$)/.exec(path);
        if (pathExtMatch) {
            const NON_DL = new Set(["js","json","html","htm","css","xml","svg","map","ts","jsx","tsx","wasm","php","aspx"]);
            if (!NON_DL.has(pathExtMatch[1])) return false;
        }

        const apiPath = /(?:^|\/)(api|graphql|rpc|ajax|batchexecute)(?:\/|$)/i.test(path)
            || path.includes("/_/");

        const dlValue = (u.searchParams.get("dl") || "").toLowerCase();
        const explicitDownload = path.includes("/download/")
            || u.searchParams.has("download")
            || dlValue === "1" || dlValue === "true" || dlValue === "yes" || dlValue === "download"
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
            && (!pathExtMatch || fn === "response.bin" || fn === "response"
                || mt.startsWith("application/json") || mt.startsWith("text/plain")
                || mt.startsWith("text/javascript"))) {
            return true;
        }

        if (u.searchParams.has("rpcids") && u.searchParams.get("rt") === "c") return true;

        if ((fn === "response.bin" || fn === "response")
            && (path.includes("/api/") || mt.startsWith("application/json")
                || mt.startsWith("text/plain") || mt.startsWith("text/javascript"))) {
            return true;
        }
    } catch {}
    return false;
}

// ── shouldIntercept ───────────────────────────────────────────────────────────

/**
 * Decide whether Stellar should intercept this download.
 * @param {string} url
 * @param {string|null} mimeType
 * @param {string} [filenameHint]  filename from download item (may have extension even if URL doesn't)
 * @param {boolean} [explicitIntent]  true when the user explicitly initiated a download
 *   (e.g. clicked <a download>, programmatic .click() intercepted, or Content-Disposition: attachment)
 * @returns {Promise<boolean>}
 */
export async function shouldIntercept(url, mimeType, filenameHint, explicitIntent = false) {
    if (!url || url.startsWith("data:") || url.startsWith("blob:")) return false;
    if (!url.startsWith("http://") && !url.startsWith("https://") && !url.startsWith("ftp://"))
        return false;

    // Skip internal API/RPC traffic unless the user explicitly initiated it as a download.
    if (!explicitIntent && isApiRpcRequest(url, filenameHint, mimeType)) return false;

    const settings = await getSettings();
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

    // Filter out inline resource types
    if (mimeType) {
        const PASS_THROUGH = ["text/html", "text/css", "application/javascript", "image/svg", "image/gif", "image/png", "image/jpeg", "image/webp"];
        if (PASS_THROUGH.some(t => mimeType.startsWith(t))) return false;
    }

    // Determine best file extension: URL path first, then filename hint.
    let ext = getUrlExtension(url);
    if (!ext && filenameHint) {
        const dotIdx = filenameHint.lastIndexOf(".");
        if (dotIdx >= 0) ext = filenameHint.slice(dotIdx + 1).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    // If we have a known extension: intercept only if it's in the monitored list.
    // Media extensions (audio/video) are always allowed when intent is explicit.
    if (ext) {
        if (explicitIntent) return settings.monitoredExtensions.has(ext);
        const MEDIA_EXTS = new Set(["mp3","m4a","aac","ogg","wav","wma","flac","aif","ra",
            "mp4","m4v","mkv","avi","mov","wmv","webm","mpeg","mpg","3gp","ogv","rm","rmvb","asf","qt"]);
        if (MEDIA_EXTS.has(ext)) return false; // media without explicit intent = playback link, not download
        return settings.monitoredExtensions.has(ext);
    }

    // Explicit user intent with no extension info: trust the click (e.g. blob-resolved API URL).
    if (explicitIntent) return true;

    // No extension info — fall back to MIME type mapping.
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
        // Generic video/audio catch-alls: intercept only if the user monitors any video/audio type.
        if (mimeType.startsWith("video/")) {
            const VIDEO_EXTS = ["mp4","mkv","avi","mov","wmv","flv","webm","m4v","mpg","mpeg","3gp","ogv","rm","rmvb","asf","qt"];
            return VIDEO_EXTS.some(e => settings.monitoredExtensions.has(e));
        }
        if (mimeType.startsWith("audio/")) {
            const AUDIO_EXTS = ["mp3","aac","wav","flac","ogg","m4a","wma","ra","aif","mpa"];
            return AUDIO_EXTS.some(e => settings.monitoredExtensions.has(e));
        }
        // application/octet-stream and other generic binary: unknown type, do not intercept.
    }

    return false;
}

// ── Messaging helpers ─────────────────────────────────────────────────────────

/**
 * Send a download request to the Stellar native host.
 */
export async function requestDownload(details) {
    return sendMessage({
        type:         "download",
        url:          details.url,
        filename:     details.filename  ?? "",
        referrer:     details.referrer  ?? "",
        pageUrl:      details.pageUrl   ?? "",
        cookies:      details.cookies   ?? "",
        modifierKey:  details.modifierKey ?? 0,
    });
}

/**
 * Ping the native host to check if Stellar is running.
 */
export async function ping() {
    try {
        const resp = await sendMessage({ type: "ping" });
        return resp?.type === "ready";
    } catch {
        return false;
    }
}

/**
 * Extract the best filename from a URL + optional Content-Disposition header.
 */
export function extractFilename(url, contentDisposition) {
    if (contentDisposition) {
        const match = contentDisposition.match(/filename\*?=(?:UTF-8'')?["']?([^"';\n]+)/i);
        if (match) return decodeURIComponent(match[1].trim());
    }
    try {
        const pathname = new URL(url).pathname;
        const name = pathname.split("/").pop();
        if (name) return decodeURIComponent(name);
    } catch { /* ignore */ }
    return "download";
}

/**
 * Low-level wrapper around chrome.runtime.sendNativeMessage (MV3).
 */
function sendMessage(msg) {
    return new Promise((resolve, reject) => {
        chrome.runtime.sendNativeMessage(NATIVE_HOST_ID, msg, (response) => {
            if (chrome.runtime.lastError) {
                reject(new Error(chrome.runtime.lastError.message));
            } else {
                resolve(response);
            }
        });
    });
}
