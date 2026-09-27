// Stellar Download Manager — Firefox background script
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

// Firefox keeps blocking webRequest in MV3, so downloads are caught the way IDM
// does it: at onHeadersReceived, on the real response (status, Content-Type,
// Content-Disposition). The listener returns a Promise and cancels the browser's
// request only after Stellar has acknowledged the hand-off; if Stellar declines
// or cannot be reached, the browser downloads the file as if the extension were
// not there.

import { ext } from "./shared/ext.js";
import { installCommon } from "./shared/background-common.js";
import { decisionSettings } from "./shared/settings.js";
import { isBypassClick, takeClick } from "./shared/clicks.js";
import { isBrowserDownloadResponse, parseContentDisposition, shouldIntercept } from "./shared/policy.js";
import { cookieHeaderFor, cookieStoreForTab } from "./shared/cookies.js";
import { sendDownload } from "./shared/native.js";
import { tabContext } from "./shared/sitecontrol.js";
import { RequestTracker, headerValue } from "./shared/tracker.js";

const tracker = new RequestTracker();
tracker.install({ extraHeaders: false });

// Navigations only. Sub-resources (images, media, <embed>, XHR, ...) are how
// pages display content; taking them breaks players and embedded viewers.
const CANDIDATE_TYPES = ["main_frame", "sub_frame", "other"];

// 204/205 carry no body; 3xx are followed by the browser and re-enter here with
// the final response.
function isFileResponse(statusCode) {
    return statusCode >= 200 && statusCode < 300 && statusCode !== 204 && statusCode !== 205;
}

// A download clicked with target=_blank leaves an empty tab behind once its
// request is cancelled (the browser would have closed it on its own).
async function closeOrphanedTab(tabId) {
    try {
        const tab = await ext.tabs.get(tabId);
        if (tab.url === "about:blank" && tab.openerTabId !== undefined) await ext.tabs.remove(tabId);
    } catch { /* tab already gone */ }
}

async function evaluate(d) {
    const settings = await decisionSettings();
    const rec = tracker.get(d.requestId);
    const disposition = parseContentDisposition(headerValue(d.responseHeaders, "content-disposition"));
    const contentType = headerValue(d.responseHeaders, "content-type") ?? "";
    const originalUrl = rec?.originalUrl ?? d.url;
    const click = takeClick(d.url, originalUrl);
    const userIntent = !!click?.downloadAttr;

    // "other" also covers prefetches and similar background fetches the user
    // never asked for; only an explicit download signal makes one a download.
    if (d.type === "other" && !disposition.attachment && !userIntent) return {};
    const ctx = await tabContext([d.tabId], [click?.pageUrl, d.originUrl, d.documentUrl]);
    if (ctx.paused) return {};
    const browserDownload = isBrowserDownloadResponse(contentType, disposition.attachment) || userIntent;

    const wanted = shouldIntercept({
        url: d.url,
        originalUrl,
        mime: contentType,
        filename: disposition.filename || click?.filename || "",
        attachment: disposition.attachment,
        userIntent,
        browserDownload,
        pageUrl: ctx.pageUrl,
    }, settings);
    if (!wanted || isBypassClick(click, settings)) return {};

    // The Cookie header Firefox actually sent (none at all is a valid answer);
    // the cookie store is only consulted if the request went unobserved.
    const cookies = rec
        ? rec.cookieHeader ?? ""
        : await cookieHeaderFor(d.url, d.cookieStoreId ?? await cookieStoreForTab(d.tabId));
    try {
        await sendDownload({
            // The final URL: the original may be a one-time link the browser has
            // already spent on its redirect.
            url: d.url,
            filename: disposition.filename || click?.filename || "",
            referrer: rec?.referrer || d.originUrl || "",
            pageUrl: click?.pageUrl || ctx.pageUrl || d.documentUrl || d.originUrl || "",
            cookies,
        });
    } catch (err) {
        console.warn("[Stellar] Hand-off failed; leaving the download to Firefox:", err?.message ?? err);
        return {};
    }
    if (d.type === "main_frame") setTimeout(() => closeOrphanedTab(d.tabId), 0);
    return { cancel: true };
}

ext.webRequest.onHeadersReceived.addListener(
    (d) => {
        // Cheap synchronous filters first: most navigations are pages and
        // resolve here without an async hop. tabId -1 covers the browser's and
        // other extensions' own requests.
        if (d.tabId < 0 || d.method !== "GET" || !isFileResponse(d.statusCode)) return undefined;
        return evaluate(d).catch((err) => {
            console.error("[Stellar] Interception failed:", err);
            return {};
        });
    },
    { urls: ["<all_urls>"], types: CANDIDATE_TYPES },
    ["blocking", "responseHeaders"],
);

installCommon();
