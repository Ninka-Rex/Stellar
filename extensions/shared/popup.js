// Stellar Download Manager — Extension Popup (Chrome and Firefox)
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

"use strict";

const ext = globalThis.browser ?? globalThis.chrome;

const $ = (id) => document.getElementById(id);
const statusIcon   = $("statusIcon");
const statusText   = $("statusText");
const accessEl     = $("access");
const enabledBox   = $("enabled");
const siteEl       = $("site");
const siteNameEl   = $("siteName");
const pauseBox     = $("pauseTab");
const excludeBox   = $("excludeSite");
const excludeLabel = $("excludeLabel");
const excludeHint  = $("excludeHint");
const siteNoteEl   = $("siteNote");

// The tab the popup was opened on; every per-site action targets it.
let activeTabId = -1;

// The app's theme arrives asynchronously; the last one seen is cached so the
// popup opens in it straight away instead of flashing the browser's theme.
const THEME_CACHE_KEY = "stellarTheme";
function applyTheme(darkMode) {
    const theme = typeof darkMode === "boolean"
        ? (darkMode ? "dark" : "light")
        : (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.dataset.theme = theme;
    if (typeof darkMode === "boolean") {
        try { localStorage.setItem(THEME_CACHE_KEY, theme); } catch { /* storage unavailable */ }
    }
}
{
    let cached = null;
    try { cached = localStorage.getItem(THEME_CACHE_KEY); } catch { /* storage unavailable */ }
    applyTheme(cached === "dark" ? true : cached === "light" ? false : null);
}

// The two browsers ship different icon files; the manifest is the one source.
// Manifest paths are relative to the package root, not to this page.
$("logo").src = ext.runtime.getURL(ext.runtime.getManifest().icons["48"]);

function send(message) {
    return ext.runtime.sendMessage(message);
}

function setStatus(text, online, detail = "") {
    statusText.textContent = text;
    statusText.title = detail;
    statusIcon.src = online ? "icons/network-online.svg" : "icons/network-offline.svg";
    statusIcon.hidden = false;
}

function showError(err) {
    setStatus("Error", false, err?.message ?? String(err));
}

function setRowDisabled(box, disabled) {
    box.disabled = disabled;
    box.closest(".check").classList.toggle("disabled", disabled);
}

function showSite(info, enabled) {
    // Browser-internal pages (settings, new tab, ...) have no site to act on.
    siteEl.hidden = !info?.site;
    if (!info?.site) return;
    siteNameEl.textContent = info.site;
    siteNameEl.title = info.site;

    pauseBox.checked = info.paused;
    excludeLabel.textContent = `Never intercept on ${info.site}`;
    excludeBox.checked = info.siteExcluded;
    // A wildcard pattern the user wrote covers this site; that is edited in
    // Stellar, so the box shows the state but cannot undo it.
    const byPattern = info.siteExcluded && !info.siteEntry;

    // Per-site choices mean nothing while interception is off everywhere.
    setRowDisabled(pauseBox, !enabled);
    setRowDisabled(excludeBox, !enabled || byPattern);

    excludeHint.textContent = byPattern ? "Set by a pattern in Preferences → Browser"
                                        : "Saved to Preferences → Browser";
    const note = enabled ? "" : "Interception is off for all sites.";
    siteNoteEl.textContent = note;
    siteNoteEl.hidden = !note;
}

async function refreshState() {
    try {
        const state = await send({ type: "getState", tabId: activeTabId });
        applyTheme(state?.darkMode);
        const enabled = state?.enabled !== false;
        enabledBox.checked = enabled;
        accessEl.hidden = state?.siteAccess !== false;
        showSite(state?.tab ?? null, enabled);
    } catch (err) {
        showError(err);
    }
}

const NOT_INSTALLED_DETAIL = "Install Stellar and open it once to register it with the browser.";

async function checkConnection() {
    try {
        const resp = await send({ type: "ping" });
        if (resp?.alive) setStatus("Connected", true);
        else if (resp?.error) setStatus("Not installed", false, NOT_INSTALLED_DETAIL);
        else setStatus("Not running", false);
    } catch (err) {
        showError(err);
    }
}

// Applies a change and then re-reads the real state, so a failed change puts
// the checkbox back instead of leaving it showing something untrue.
async function commit(box, message) {
    box.disabled = true;
    try {
        const resp = await send(message);
        if (resp?.ok === false) throw new Error(resp.error);
    } catch (err) {
        showError(err);
    }
    box.disabled = false;
    await refreshState();
}

enabledBox.addEventListener("change", () =>
    commit(enabledBox, { type: "setEnabled", value: enabledBox.checked }));

pauseBox.addEventListener("change", () =>
    commit(pauseBox, { type: "setTabPaused", tabId: activeTabId, paused: pauseBox.checked }));

// The site list lives in the app, so this needs the native host.
excludeBox.addEventListener("change", () =>
    commit(excludeBox, { type: "setSiteExcluded", tabId: activeTabId, exclude: excludeBox.checked }));

// permissions.request must run directly inside the user's click.
$("grantAccess").addEventListener("click", async () => {
    try {
        await ext.permissions.request({ origins: ["<all_urls>"] });
    } catch (err) {
        showError(err);
    }
    refreshState();
});

$("openApp").addEventListener("click", async (event) => {
    const button = event.currentTarget;
    // A cold start makes the host wait for the GUI before answering.
    button.disabled = true;
    button.textContent = "Opening…";
    try {
        const resp = await send({ type: "focus" });
        if (resp?.ok === false) throw new Error(resp.error);
        window.close();
    } catch {
        button.disabled = false;
        button.textContent = "Open Stellar";
        setStatus("Not installed", false, NOT_INSTALLED_DETAIL);
    }
});

(async () => {
    try {
        const [tab] = await ext.tabs.query({ active: true, currentWindow: true });
        if (Number.isInteger(tab?.id)) activeTabId = tab.id;
    } catch { /* no active tab: site controls stay hidden */ }
    refreshState();
})();
checkConnection();
