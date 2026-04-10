// Stellar Download Manager - Chrome Extension Popup
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

document.addEventListener("DOMContentLoaded", async () => {
    const statusEl   = document.getElementById("status");
    const toggleBtn  = document.getElementById("toggleBtn");
    const openAppBtn = document.getElementById("openApp");

    function updateToggleBtn(enabled) {
        toggleBtn.textContent = enabled ? "Interception: ON" : "Interception: OFF";
        toggleBtn.className   = enabled ? "btn btn-on" : "btn btn-off";
        toggleBtn.dataset.enabled = String(enabled);
    }

    function checkConnection() {
        chrome.runtime.sendMessage({ type: "ping" }, (resp) => {
            const err = chrome.runtime.lastError;
            if (err) {
                statusEl.textContent = "Error: " + err.message;
                statusEl.className   = "status-offline";
            } else if (!resp?.alive) {
                statusEl.textContent = resp?.error
                    ? "Native host not available. Install Stellar."
                    : "Not running. Install and launch Stellar.";
                statusEl.className   = "status-offline";
            } else {
                statusEl.textContent = "Connected to Stellar.";
                statusEl.className   = "status-online";
            }
        });
    }

    chrome.runtime.sendMessage({ type: "getSettings" }, (resp) => {
        if (chrome.runtime.lastError) return;
        const enabled = resp?.enabled !== false;
        updateToggleBtn(enabled);
    });

    checkConnection();

    toggleBtn.addEventListener("click", () => {
        const wasEnabled = toggleBtn.dataset.enabled === "true";
        const nowEnabled = !wasEnabled;
        chrome.runtime.sendMessage({ type: "setEnabled", value: nowEnabled }, (resp) => {
            if (chrome.runtime.lastError || resp?.ok === false) {
                statusEl.textContent = "Could not update interception state.";
                statusEl.className = "status-offline";
                return;
            }
            updateToggleBtn(nowEnabled);
            checkConnection();
        });
    });

    openAppBtn.addEventListener("click", () => {
        chrome.runtime.sendMessage({ type: "focus" }, (resp) => {
            if (chrome.runtime.lastError || resp?.ok === false) {
                statusEl.textContent = "Native host not available. Open Stellar once to register it.";
                statusEl.className = "status-offline";
                return;
            }
            window.close();
        });
    });
});
