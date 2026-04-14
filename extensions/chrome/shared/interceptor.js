// extensions/shared/interceptor.js
// webRequest / declarativeNetRequest helpers for intercepting downloads.
// Imported by the service worker of each browser's extension.

import { requestDownload, extractFilename, shouldIntercept } from "./messaging.js";

// Track last modifier key state to detect bypass requests.
let lastModifierKey = 0;
let lastModifierKeyTime = 0;
const MODIFIER_KEY_TIMEOUT = 10000;

// Guard against repeated download-created events for the same URL while a
// handoff is already in progress.
const pendingUrls = new Set();

export function recordModifierKey(modifierKey) {
    lastModifierKey = modifierKey;
    lastModifierKeyTime = Date.now();
    setTimeout(() => {
        if (Date.now() - lastModifierKeyTime >= MODIFIER_KEY_TIMEOUT) {
            lastModifierKey = 0;
        }
    }, MODIFIER_KEY_TIMEOUT);
}

function getAndClearModifierKey() {
    const now = Date.now();
    if (now - lastModifierKeyTime >= MODIFIER_KEY_TIMEOUT) {
        return 0;
    }
    const key = lastModifierKey;
    lastModifierKey = 0;
    return key;
}

function forceIntercept(url) {
    try {
        const u = new URL(url);
        const host = u.hostname.toLowerCase();
        const path = u.pathname.toLowerCase();
        const isDriveUserContent = host === "drive.usercontent.google.com"
            || host.endsWith(".drive.usercontent.google.com");
        if (isDriveUserContent) return true;

        const isGoogleDocHost = host === "drive.google.com"
            || host.endsWith(".drive.google.com")
            || host === "docs.google.com"
            || host.endsWith(".docs.google.com");
        if (!isGoogleDocHost) return false;

        // Force-intercept only true file download endpoints, not webapp APIs,
        // thumbnail/viewer calls, or other in-page assets.
        if (path === "/uc" || path.includes("/download/")) return true;
        if (u.searchParams.get("export") === "download") return true;
        if (u.searchParams.has("response-content-disposition")) return true;
        return false;
    } catch {
        return false;
    }
}

export async function handleDownloadCreated(downloadItem) {
    const { url, filename, referrer, mime } = downloadItem;
    if (!url || pendingUrls.has(url)) {
        return;
    }

    const modifierKey = getAndClearModifierKey();
    if (modifierKey > 0) {
        return;
    }

    if (!forceIntercept(url) && !(await shouldIntercept(url, mime, filename))) {
        return;
    }

    pendingUrls.add(url);
    setTimeout(() => pendingUrls.delete(url), 15000);

    try {
        await chrome.downloads.cancel(downloadItem.id);
    } catch {}
    try {
        await chrome.downloads.erase({ id: downloadItem.id });
    } catch {}

    const name = filename || extractFilename(url);

    let pageUrl = "";
    try {
        const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tabs.length > 0) {
            pageUrl = tabs[0].url || "";
        }
    } catch {}

    let cookieHeader = "";
    try {
        const urlObj = new URL(url);
        const cookieUrls = [url];
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
        await requestDownload({
            url,
            filename: name,
            referrer,
            pageUrl,
            cookies: cookieHeader,
            modifierKey: 0,
        });
    } catch (err) {
        console.error("[Stellar] Failed to send download to native host:", err);
    } finally {
        setTimeout(() => pendingUrls.delete(url), 1000);
    }
}
