// Chrome MV3 service worker – Stellar extension
import { handleDownloadCreated } from "../shared/interceptor.js";
import { ping, syncSettingsFromApp } from "../shared/messaging.js";

// ── Download interception ─────────────────────────────────────────────────────
chrome.downloads.onCreated.addListener((item) => {
    handleDownloadCreated(item);
});

// ── Context menu ──────────────────────────────────────────────────────────────
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
    // Sync settings from app so the extension uses the user's configured lists
    await syncSettingsFromApp();
});

chrome.contextMenus.onClicked.addListener(async (info) => {
    const url = info.linkUrl || info.srcUrl || info.pageUrl;
    if (!url) return;
    const { requestDownload } = await import("../shared/messaging.js");
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
    await requestDownload({ url, referrer: info.frameUrl ?? info.pageUrl ?? "", pageUrl: info.pageUrl ?? "", cookies: cookieHeader });
});

// ── Extension icon badge ──────────────────────────────────────────────────────
async function updateBadge() {
    const alive = await ping();
    chrome.action.setBadgeText({ text: alive ? "" : "OFF" });
    chrome.action.setBadgeBackgroundColor({ color: alive ? "#4CAF50" : "#F44336" });
}

chrome.runtime.onStartup.addListener(async () => {
    updateBadge();
    await syncSettingsFromApp();
});
updateBadge();
