// Stellar Download Manager — Firefox Extension Popup
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

"use strict";

document.addEventListener("DOMContentLoaded", async () => {
    const statusEl   = document.getElementById("status");
    const toggleBtn  = document.getElementById("toggleBtn");
    const openAppBtn = document.getElementById("openApp");

    // ── Check connection to Stellar ───────────────────────────────────────────
    function checkConnection() {
        browser.runtime.sendMessage({ type: "ping" }, (resp) => {
            const err = browser.runtime.lastError;
            if (err) {
                statusEl.textContent = "Error: " + err.message;
                statusEl.className   = "status-offline";
            } else if (!resp?.alive) {
                statusEl.textContent = "Not running. (native error: " + (resp?.error ?? "unknown") + ")";
                statusEl.className   = "status-offline";
            } else {
                statusEl.textContent = "Connected to Stellar.";
                statusEl.className   = "status-online";
            }
        });
    }
    checkConnection();

    // ── Load current enabled state ────────────────────────────────────────────
    browser.runtime.sendMessage({ type: "getSettings" }, (resp) => {
        if (browser.runtime.lastError) return;
        const enabled = resp?.enabled !== false;
        updateToggleBtn(enabled);
    });

    function updateToggleBtn(enabled) {
        toggleBtn.textContent = enabled ? "Interception: ON" : "Interception: OFF";
        toggleBtn.className   = enabled ? "btn btn-on" : "btn btn-off";
        toggleBtn.dataset.enabled = String(enabled);
    }

    toggleBtn.addEventListener("click", () => {
        const wasEnabled = toggleBtn.dataset.enabled === "true";
        const nowEnabled = !wasEnabled;
        browser.runtime.sendMessage({ type: "setEnabled", value: nowEnabled }, () => {
            updateToggleBtn(nowEnabled);
        });
    });

    // ── Open Stellar ──────────────────────────────────────────────────────────
    openAppBtn.addEventListener("click", () => {
        browser.runtime.sendMessage({ type: "focus" }, () => {});
        window.close();
    });
});
