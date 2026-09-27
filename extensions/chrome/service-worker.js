// Stellar Download Manager — Chrome MV3 service worker
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

// MV3 Chrome has no blocking webRequest, so a download is caught after Chrome
// has turned a response into a download, and held there while Stellar decides:
//   onCreated              — pause it at once, so no bandwidth is spent and the
//                            file cannot finish (and be saved twice) meanwhile;
//   onDeterminingFilename  — returning true defers the filename, and with it any
//                            "Save as" dialog, until the decision is made.
// Taken: cancel + erase. Declined or unreachable: resume, and Chrome finishes it
// as if the extension were not there. Request details the downloads API lacks
// (method, the Cookie header actually sent, the tab) come from the tracker.

import { ext } from "./shared/ext.js";
import { installCommon } from "./shared/background-common.js";
import { decisionSettings } from "./shared/settings.js";
import { isBypassClick, takeClick } from "./shared/clicks.js";
import { baseName, isTransferableUrl, parseContentDisposition, shouldIntercept } from "./shared/policy.js";
import { cookieHeaderFor } from "./shared/cookies.js";
import { sendDownload } from "./shared/native.js";
import { tabContext } from "./shared/sitecontrol.js";
import { RequestTracker } from "./shared/tracker.js";

const tracker = new RequestTracker();
tracker.install({ extraHeaders: true });

// Chrome's fixed cookie store ids, used when no request was observed.
const DEFAULT_STORE = "0";
const INCOGNITO_STORE = "1";

// onDeterminingFilename normally follows onCreated immediately. If it never
// comes, a held download must not stay paused forever.
const HOLD_TIMEOUT_MS = 10000;

const held = new Map(); // downloadId -> { paused: Promise<boolean>, timer, deciding }

function isCandidate(item) {
    return item.state === "in_progress"
        && item.byExtensionId !== ext.runtime.id
        && isTransferableUrl(item.finalUrl || item.url);
}

async function release(id) {
    const entry = held.get(id);
    held.delete(id);
    if (!entry) return;
    clearTimeout(entry.timer);
    if (await entry.paused) await ext.downloads.resume(id).catch(() => {});
}

async function take(id) {
    const entry = held.get(id);
    held.delete(id);
    if (entry) clearTimeout(entry.timer);
    await ext.downloads.cancel(id).catch(() => {});
    await ext.downloads.erase({ id }).catch(() => {});
}

// Resolves true once Stellar has accepted the download.
async function handOff(item) {
    const url = item.finalUrl || item.url;
    const settings = await decisionSettings();
    const rec = tracker.findByUrl(url, item.url);
    // A POST body cannot be replayed by the app; the browser keeps those.
    if (rec && rec.method !== "GET") return false;

    const click = takeClick(url, item.url);
    const ctx = await tabContext([rec?.tabId, click?.tabId], [click?.pageUrl, item.referrer, rec?.initiator]);
    if (ctx.paused) return false;
    const disposition = parseContentDisposition(rec?.contentDisposition);
    // Chrome has already resolved Content-Disposition and the `download`
    // attribute into item.filename.
    const filename = baseName(item.filename) || disposition.filename || click?.filename || "";

    const wanted = shouldIntercept({
        url,
        originalUrl: item.url,
        mime: item.mime || rec?.contentType || "",
        filename,
        attachment: disposition.attachment,
        userIntent: !!click?.downloadAttr,
        browserDownload: true,
        pageUrl: ctx.pageUrl,
    }, settings);
    if (!wanted || isBypassClick(click, settings)) return false;

    // The Cookie header Chrome actually sent (none at all is a valid answer);
    // the cookie store is only consulted if the request went unobserved.
    const cookies = rec
        ? rec.cookieHeader ?? ""
        : await cookieHeaderFor(url, item.incognito ? INCOGNITO_STORE : DEFAULT_STORE);

    await sendDownload({
        // The final URL: the original may be a one-time link Chrome has already
        // spent on its redirect.
        url,
        filename,
        referrer: item.referrer || rec?.referrer || "",
        pageUrl: click?.pageUrl || ctx.pageUrl || item.referrer || "",
        cookies,
    });
    return true;
}

ext.downloads.onCreated.addListener((item) => {
    if (!isCandidate(item)) return;
    const entry = {
        paused: ext.downloads.pause(item.id).then(() => true, () => false),
        timer: 0,
        deciding: false,
    };
    entry.timer = setTimeout(() => { if (!entry.deciding) release(item.id); }, HOLD_TIMEOUT_MS);
    held.set(item.id, entry);
});

ext.downloads.onDeterminingFilename.addListener((item, suggest) => {
    // Returning nothing lets Chrome pick the name immediately.
    if (!isCandidate(item)) return undefined;
    const entry = held.get(item.id);
    if (entry) entry.deciding = true;

    handOff(item)
        .catch((err) => {
            console.warn("[Stellar] Hand-off failed; leaving the download to Chrome:", err?.message ?? err);
            return false;
        })
        .then((taken) => (taken ? take(item.id) : release(item.id)))
        .finally(() => {
            // Chrome waits for every listener's answer; a cancelled download
            // may reject it, which is harmless.
            try { suggest(); } catch { /* download already gone */ }
        });
    return true;
});

installCommon();
