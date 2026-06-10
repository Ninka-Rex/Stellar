// Stellar Download Manager — Shared Download-Interception Helpers
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

// Modifier-key bypass tracking, the host-agnostic forceIntercept() test, and the
// chrome.downloads.onCreated handler. Imported by service-worker.js.

import { requestDownload, extractFilename, shouldIntercept, ping, passesGlobalGate } from "./messaging.js";

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

// Host-agnostic "this is clearly a download, capture it even without a file
// extension" test. Cloud download endpoints (Google Drive, Dropbox, Nextcloud,
// WeTransfer, S3 presigned, ...) expose extensionless URLs like
// "/download?id=...", "/uc?export=download", "/s/<id>/download" that carry an
// explicit download signal but no ".ext" for the normal monitored-extension
// matcher to catch. Matching on those signals — not on a hostname allowlist —
// covers every such host uniformly. Restricted to extensionless URLs so a normal
// "video.mp4" link is still left to the extension/MIME matcher and its media
// carve-outs. The master ON/OFF toggle and exclusion lists are enforced
// separately at each call site (forceIntercept only overrides ext/MIME matching).
//
// `atDownloadCreated` distinguishes the two call sites' trust levels. At
// chrome.downloads.onCreated the browser already turned the URL into a real
// download (server sent Content-Disposition/attachment) — ground truth — so the
// weak bare-path signals ("/download", "/download/") are trustworthy. At click
// time there is no server response yet, and a bare-path match cannot tell a
// genuine download action ("/s/<id>/download") from an ordinary directory named
// "download" (e.g. github.com/.../app/src/download) — pre-intercepting the latter
// hijacks plain navigation. So at click time we require an explicit query-param
// download signal; bare-path cloud downloads still get caught later by onCreated.
export function forceIntercept(url, atDownloadCreated = true) {
    try {
        const u = new URL(url);
        const path = u.pathname.toLowerCase();
        const sp = u.searchParams;

        const lastSeg = path.split("/").pop() || "";
        if (lastSeg.includes(".")) return false; // has an extension → not forced

        const dlValue = (sp.get("dl") || "").toLowerCase();
        const dlIntent = dlValue === "1" || dlValue === "true" || dlValue === "yes" || dlValue === "download";

        // Query-param signals: unambiguous, safe at click time too.
        const querySignal = sp.get("export") === "download"
            || sp.get("alt") === "media"
            || sp.has("response-content-disposition")
            || sp.has("attachment")
            || sp.has("filename")
            || sp.has("download")
            || dlIntent;
        if (querySignal) return true;

        // Path-only signals: ambiguous (a "/download" segment may just be a
        // directory). Trust them only once the browser has confirmed a download.
        if (!atDownloadCreated) return false;
        return path === "/uc"
            || path.endsWith("/download")
            || path.includes("/download/");
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

    // forceIntercept overrides only the extension/MIME matching — it must still
    // honour the master ON/OFF toggle and exclusion lists (passesGlobalGate).
    const forced = forceIntercept(url) && await passesGlobalGate(url);
    if (!forced && !(await shouldIntercept(url, mime, filename))) return;

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
