// Stellar Download Manager — Content script (Chrome and Firefox)
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

// Observes only. Interception happens in the background script on the real
// network response, so this script never cancels a click, never delays it and
// injects nothing into the page's own JavaScript. It reports the two facts a
// response cannot carry: which modifier keys were held, and the `download`
// attribute (with its suggested filename) of the clicked link.

"use strict";

(() => {
    const ext = globalThis.browser ?? globalThis.chrome;

    function clickedLink(event) {
        // composedPath() reaches links inside open shadow roots, which
        // event.target (retargeted to the shadow host) does not.
        for (const node of event.composedPath()) {
            if (node instanceof HTMLAnchorElement || node instanceof HTMLAreaElement) return node;
        }
        return null;
    }

    window.addEventListener("click", (event) => {
        // Synthetic clicks come from page script, which could otherwise claim a
        // bypass or a download intent the user never expressed.
        if (!event.isTrusted || event.button !== 0) return;
        const link = clickedLink(event);
        if (!link) return;
        const downloadAttr = link.hasAttribute("download");
        if (!downloadAttr && !event.altKey && !event.ctrlKey && !event.shiftKey) return;
        const url = link.href;
        if (!/^(?:https?|ftp):/i.test(url)) return;
        ext.runtime.sendMessage({
            type: "linkClick",
            url,
            downloadAttr,
            filename: downloadAttr ? link.getAttribute("download") : "",
            alt: event.altKey,
            ctrl: event.ctrlKey,
            shift: event.shiftKey,
        }).catch(() => { /* extension reloading; the click proceeds normally */ });
    }, { capture: true });

    // Every <a href> inside the current selection, for "Download all links".
    function collectSelectedLinks() {
        const sel = window.getSelection();
        if (!sel || sel.rangeCount === 0) return [];
        const out = [];
        const seen = new Set();
        const push = (a) => {
            // Cloned-fragment anchors lose their resolved .href in some engines,
            // so the raw attribute is resolved against the page URL.
            const raw = a.getAttribute("href");
            if (!raw) return;
            let href;
            try { href = new URL(raw, document.baseURI).href; } catch { return; }
            if (seen.has(href)) return;
            if (!/^(?:https?:|ftp:|magnet:\?)/i.test(href)) return;
            seen.add(href);
            out.push({ url: href, text: (a.textContent || "").trim().slice(0, 300) });
        };
        for (let i = 0; i < sel.rangeCount; i++)
            sel.getRangeAt(i).cloneContents().querySelectorAll("a[href]").forEach(push);
        return out;
    }

    ext.runtime.onMessage.addListener((msg, sender, sendResponse) => {
        if (msg?.type !== "collectSelectedLinks") return false;
        sendResponse(collectSelectedLinks());
        return false;
    });
})();
