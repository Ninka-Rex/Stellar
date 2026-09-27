// Stellar Download Manager — Link-click intents reported by the content script
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

import { BYPASS_ALT, BYPASS_CTRL, BYPASS_SHIFT } from "./settings.js";
import { isTransferableUrl } from "./policy.js";

// A click and the download it starts are keyed by URL, so a modifier held for
// one link can never leak onto an unrelated request (an image, another tab).
const CLICK_TTL_MS = 10000;
const MAX_CLICKS = 100;
const clicks = new Map();

function prune() {
    const cutoff = Date.now() - CLICK_TTL_MS;
    for (const [url, click] of clicks) {
        if (click.at < cutoff || clicks.size > MAX_CLICKS) clicks.delete(url);
    }
}

// `message` comes from a content script in an arbitrary page: every field is
// type-checked. A page cannot forge a trusted click — the content script only
// reports `isTrusted` events — and a click can only *add* a filename hint or a
// bypass; it never makes a non-download URL downloadable on its own.
export function recordClick(message, sender) {
    const url = typeof message.url === "string" ? message.url : "";
    if (!url || url.length > 8192 || !isTransferableUrl(url)) return;
    prune();
    clicks.set(url, {
        at: Date.now(),
        downloadAttr: message.downloadAttr === true,
        filename: typeof message.filename === "string" ? message.filename.slice(0, 1024) : "",
        alt: message.alt === true,
        ctrl: message.ctrl === true,
        shift: message.shift === true,
        pageUrl: typeof sender.tab?.url === "string" ? sender.tab.url : "",
        tabId: Number.isInteger(sender.tab?.id) ? sender.tab.id : -1,
    });
}

// Returns and forgets the click that led to `urls` (tried in order: e.g. the
// final URL, then the pre-redirect URL). Consuming it keeps one click from
// steering two downloads.
export function takeClick(...urls) {
    prune();
    for (const url of urls) {
        if (!url) continue;
        const click = clicks.get(url);
        if (click) {
            clicks.delete(url);
            return click;
        }
    }
    return null;
}

export function isBypassClick(click, settings) {
    if (!click) return false;
    switch (settings.bypassKey) {
    case BYPASS_ALT:   return click.alt;
    case BYPASS_CTRL:  return click.ctrl;
    case BYPASS_SHIFT: return click.shift;
    default:           return false;
    }
}
