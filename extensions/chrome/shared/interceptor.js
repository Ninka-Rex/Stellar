// extensions/shared/interceptor.js
// webRequest / declarativeNetRequest helpers for intercepting downloads.
// Imported by the service worker of each browser's extension.

import { requestDownload, extractFilename, shouldIntercept, ping } from "./messaging.js";

// Track last modifier key state to detect bypass requests
// Auto-clears after 10 seconds (downloads are typically created instantly)
let lastModifierKey = 0;
let lastModifierKeyTime = 0;
const MODIFIER_KEY_TIMEOUT = 10000;  // 10 seconds
const FALLBACK_SUPPRESS_TTL_MS = 15000;
const suppressedUrls = new Map();

export function recordModifierKey(modifierKey) {
    lastModifierKey = modifierKey;
    lastModifierKeyTime = Date.now();
    // Auto-clear after timeout
    setTimeout(() => {
        if (Date.now() - lastModifierKeyTime >= MODIFIER_KEY_TIMEOUT) {
            lastModifierKey = 0;
        }
    }, MODIFIER_KEY_TIMEOUT);
}

function getAndClearModifierKey() {
    const now = Date.now();
    if (now - lastModifierKeyTime >= MODIFIER_KEY_TIMEOUT) {
        return 0;  // Expired
    }
    const key = lastModifierKey;
    lastModifierKey = 0;  // Consume it
    return key;
}

function isSuppressedUrl(url) {
    const expiresAt = suppressedUrls.get(url);
    if (!expiresAt) return false;
    if (expiresAt <= Date.now()) {
        suppressedUrls.delete(url);
        return false;
    }
    return true;
}

function suppressUrl(url, ttlMs = FALLBACK_SUPPRESS_TTL_MS) {
    if (!url) return;
    suppressedUrls.set(url, Date.now() + ttlMs);
}

export function forceIntercept(url) {
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
        if (path === "/uc" || path.startsWith("/download") || path.includes("/download/")) return true;
        if (u.searchParams.get("export") === "download") return true;
        if (u.searchParams.has("response-content-disposition")) return true;
        if (isDriveUserContent && u.searchParams.has("id")) return true;
        return false;
    } catch { return false; }
}

export async function handleDownloadCreated(downloadItem) {
    const { url, filename, referrer, mime } = downloadItem;

    if (!url || isSuppressedUrl(url)) return;

    // If Stellar is not running, let Chrome manage the download normally.
    if (!(await ping())) return;

    // Check if bypass modifier key is active
    const modifierKey = getAndClearModifierKey();
    if (modifierKey > 0) {
        // User is bypassing interception, let browser handle it
        console.log("[Stellar] Bypass key detected, letting browser handle download");
        return;
    }

    if (!forceIntercept(url) && !(await shouldIntercept(url, mime, filename))) return;

    // Cancel the browser-managed download
    chrome.downloads.cancel(downloadItem.id);
    chrome.downloads.erase({ id: downloadItem.id });

    const name = filename || extractFilename(url);

    // Capture active tab URL as parent web page
    let pageUrl = "";
    try {
        const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tabs.length > 0) pageUrl = tabs[0].url || "";
    } catch { /* ignore */ }

    // Grab cookies for the download URL AND parent Google domains so the
    // manager can authenticate (auth cookies live on .google.com, not just
    // drive.usercontent.google.com).
    let cookieHeader = "";
    try {
        const urlObj = new URL(url);
        const cookieUrls = [url];
        // Build parent domain URLs: usercontent.google.com -> google.com
        const parts = urlObj.hostname.split(".");
        for (let i = 1; i < parts.length - 1; i++) {
            cookieUrls.push(`${urlObj.protocol}//${parts.slice(i).join(".")}/`);
        }
        const seen = new Set();
        const allCookies = [];
        for (const cu of cookieUrls) {
            const batch = await chrome.cookies.getAll({ url: cu });
            for (const c of batch) {
                if (!seen.has(c.name)) {
                    seen.add(c.name);
                    allCookies.push(c);
                }
            }
        }
        cookieHeader = allCookies.map(c => `${c.name}=${c.value}`).join("; ");
    } catch (err) {
        console.warn("[Stellar] Could not get cookies:", err);
    }

    try {
        await requestDownload({ url, filename: name, referrer, pageUrl, cookies: cookieHeader, modifierKey: 0 });
    } catch (err) {
        console.error("[Stellar] Failed to send download to native host:", err);
        // Avoid re-intercept loops while letting Chrome retry the download once.
        suppressUrl(url);
        chrome.downloads.download({ url, filename: name }).catch((fallbackErr) => {
            console.error("[Stellar] Browser fallback download failed:", fallbackErr);
        });
    }
}
