// Stellar Download Manager — Firefox Extension Content Script
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

"use strict";

// The service worker's downloads.onCreated listener handles most cases.
// This content script catches anchor clicks with the "download" attribute,
// which trigger file downloads but may not always surface through
// downloads.onCreated in time for interception.

document.addEventListener("click", (event) => {
    const anchor = event.target.closest("a[download], a[href]");
    if (!anchor) return;

    const href = anchor.href;
    if (!href || href.startsWith("javascript:") || href.startsWith("#")) return;

    // Only act on links that look like file downloads (have an extension in the
    // pathname or carry the `download` attribute). The service worker will do
    // the actual interception via downloads.onCreated; we don't need to do
    // anything here other than let the default browser behavior proceed so
    // that the download appears in the downloads.onCreated event.
    // This script is intentionally minimal — it exists as a hook point for
    // future enhancements (e.g., page-level disabling, download-bar suppression).
}, { passive: true, capture: true });
