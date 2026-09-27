// Stellar Download Manager — Request tracker
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

// Observes (never blocks) navigation-type requests and remembers what the browser
// actually sent: method, Cookie and Referer headers, original URL before
// redirects, tab. A download handed to Stellar is then replayed with the exact
// session the browser used, rather than one reconstructed from the cookie store.
//
// Records are kept briefly after completion because Chrome reports the download
// (downloads.onCreated) only once the response has started.
const RECORD_TTL_MS = 60000;
const MAX_RECORDS = 500;
const TRACKED_TYPES = ["main_frame", "sub_frame", "other"];

export function headerValue(headers, name) {
    const wanted = name.toLowerCase();
    for (const h of headers || []) {
        if ((h.name || "").toLowerCase() === wanted) return h.value ?? "";
    }
    return null;
}

export class RequestTracker {
    #records = new Map();

    // Chrome hides Cookie/Referer from webRequest unless "extraHeaders" is asked
    // for; Firefox exposes them by default and rejects the unknown option.
    install({ extraHeaders }) {
        const filter = { urls: ["<all_urls>"], types: TRACKED_TYPES };
        const wr = ext.webRequest;
        wr.onBeforeRequest.addListener((d) => this.#onBeforeRequest(d), filter);
        wr.onBeforeSendHeaders.addListener((d) => this.#onBeforeSendHeaders(d), filter,
            extraHeaders ? ["requestHeaders", "extraHeaders"] : ["requestHeaders"]);
        wr.onHeadersReceived.addListener((d) => this.#onHeadersReceived(d), filter, ["responseHeaders"]);
        wr.onCompleted.addListener((d) => this.#finish(d), filter);
        wr.onErrorOccurred.addListener((d) => this.#finish(d), filter);
    }

    get(requestId) {
        return this.#records.get(requestId) ?? null;
    }

    // Most recent record whose current or original URL is one of `urls`.
    findByUrl(...urls) {
        const wanted = new Set(urls.filter(Boolean));
        let best = null;
        for (const rec of this.#records.values()) {
            if ((wanted.has(rec.url) || wanted.has(rec.originalUrl)) && (!best || rec.at > best.at))
                best = rec;
        }
        return best;
    }

    #prune() {
        const cutoff = Date.now() - RECORD_TTL_MS;
        for (const [id, rec] of this.#records) {
            if (rec.at < cutoff || this.#records.size > MAX_RECORDS) this.#records.delete(id);
        }
    }

    // Redirects re-enter onBeforeRequest with the same requestId and a new URL.
    #onBeforeRequest(d) {
        const rec = this.#records.get(d.requestId);
        if (rec) {
            rec.url = d.url;
            rec.method = d.method;
            rec.at = Date.now();
            return;
        }
        this.#prune();
        this.#records.set(d.requestId, {
            requestId: d.requestId,
            originalUrl: d.url,
            url: d.url,
            method: d.method,
            type: d.type,
            tabId: d.tabId,
            // Origin (Chrome) or URL (Firefox) of the page that made the request.
            initiator: d.initiator ?? d.originUrl ?? "",
            cookieStoreId: d.cookieStoreId, // Firefox only
            cookieHeader: null,
            referrer: null,
            statusCode: 0,
            contentType: "",
            contentDisposition: "",
            at: Date.now(),
        });
    }

    // Fires once per redirect hop; the last hop's headers belong to the final URL.
    #onBeforeSendHeaders(d) {
        const rec = this.#records.get(d.requestId);
        if (!rec) return;
        rec.cookieHeader = headerValue(d.requestHeaders, "cookie");
        rec.referrer = headerValue(d.requestHeaders, "referer");
    }

    #onHeadersReceived(d) {
        const rec = this.#records.get(d.requestId);
        if (!rec) return;
        rec.statusCode = d.statusCode;
        rec.contentType = headerValue(d.responseHeaders, "content-type") ?? "";
        rec.contentDisposition = headerValue(d.responseHeaders, "content-disposition") ?? "";
    }

    #finish(d) {
        const rec = this.#records.get(d.requestId);
        if (rec) rec.at = Date.now();
    }
}
