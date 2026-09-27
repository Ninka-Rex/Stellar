// Stellar Download Manager — Native messaging client
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

import { ext } from "./ext.js";

export const NATIVE_HOST_ID = "com.stellar.downloadmanager";

// Every sendNativeMessage call starts a fresh Stellar host process. The host
// answers a download within a few hundred ms (it forwards over IPC, or writes the
// cold-start drop file and launches the GUI), so a timeout this long only trips
// when the host is wedged. Callers treat a timeout as "not taken" and hand the
// download back to the browser.
const NATIVE_TIMEOUT_MS = 20000;

export function nativeRequest(message, timeoutMs = NATIVE_TIMEOUT_MS) {
    let timer;
    const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("Native host did not respond in time")), timeoutMs);
    });
    return Promise.race([ext.runtime.sendNativeMessage(NATIVE_HOST_ID, message), timeout])
        .finally(() => clearTimeout(timer));
}

export async function pingNative() {
    const resp = await nativeRequest({ type: "ping" }, 5000);
    return resp?.type === "ready";
}

// Resolves only when the host confirms it accepted the download. The browser
// copy of the request may be cancelled only after this resolves; any rejection
// means the browser must keep the download.
export async function sendDownload(d) {
    const resp = await nativeRequest({
        type:        "download",
        url:         d.url,
        filename:    d.filename ?? "",
        referrer:    d.referrer ?? "",
        pageUrl:     d.pageUrl ?? "",
        cookies:     d.cookies ?? "",
        // Bypass keys are resolved in the extension against the app's configured
        // key; anything reaching the host is meant to be downloaded.
        modifierKey: 0,
    });
    if (resp?.type !== "ack")
        throw new Error(resp?.message || "Native host rejected the download");
}

export async function sendImportLinks(links, ctx) {
    const resp = await nativeRequest({
        type:     "importLinks",
        links,
        referrer: ctx.referrer ?? "",
        pageUrl:  ctx.pageUrl ?? "",
        cookies:  ctx.cookies ?? "",
    });
    if (resp?.type !== "ack")
        throw new Error(resp?.message || "Native host rejected the links");
}

// On a cold start the host launches the GUI and retries IPC for up to ~40 s
// before it answers.
const FOCUS_TIMEOUT_MS = 45000;

export function focusApp() {
    return nativeRequest({ type: "focus" }, FOCUS_TIMEOUT_MS);
}
