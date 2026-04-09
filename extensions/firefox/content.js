// Stellar Download Manager — Firefox Extension Content Script
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

"use strict";

// The service worker's downloads.onCreated listener handles most cases.
// This content script also tracks modifier keys for bypass interception.

document.addEventListener("click", (event) => {
    const anchor = event.target.closest("a[download], a[href]");
    if (!anchor) return;

    const href = anchor.href;
    if (!href || href.startsWith("javascript:") || href.startsWith("#")) return;

    // Determine which modifier key is held (0=none, 1=alt, 2=ctrl, 3=shift)
    let modifierKey = 0;
    if (event.altKey) modifierKey = 1;
    else if (event.ctrlKey) modifierKey = 2;
    else if (event.shiftKey) modifierKey = 3;

    // Notify the background script if a modifier key was held
    if (modifierKey > 0) {
        browser.runtime.sendMessage({
            type: "recordModifierKey",
            modifierKey: modifierKey,
        }).catch(() => {
            // Service worker may not be ready, ignore
        });
    }

    // The service worker's downloads.onCreated listener will do
    // the actual interception. This script just tracks modifier keys.
}, { capture: true });
