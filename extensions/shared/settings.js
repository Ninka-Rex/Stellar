// Stellar Download Manager — Interception settings
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
import { nativeRequest } from "./native.js";

// Kept in sync with AppSettings::defaultMonitoredExtensions()/defaultExcludedSites();
// used until the first successful sync with the app.
const DEFAULT_MONITORED_EXTENSIONS = [
    "3gp","7z","aac","ace","aif","apk","arj","asf","avi","bin","bz2",
    "exe","gz","gzip","img","iso","lzh","m4a","m4v","mkv","mov","mp3",
    "mp4","mpa","mpe","mpeg","mpg","msi","msu","ogg","ogv","pdf","plj",
    "pps","ppt","qt","r00","r01","ra","rar","rm","rmvb","sea","sit","sitx",
    "tar","tif","tiff","wav","wma","wmv","z","zip",
    "safetensors","gguf","azw3","unitypackage",
];

const DEFAULT_EXCLUDED_SITES = [
    "*.update.microsoft.com",
    "download.windowsupdate.com",
    "*.download.windowsupdate.com",
    "siteseal.thawte.com",
    "ecom.cimetz.com",
    "*.voice2page.com",
    "download.sophos.com",
];

// Index into the app's "bypass interception key" combo: None, Alt, Ctrl, Shift.
export const BYPASS_NONE = 0;
export const BYPASS_ALT = 1;
export const BYPASS_CTRL = 2;
export const BYPASS_SHIFT = 3;
const DEFAULT_BYPASS_KEY = BYPASS_ALT;

const STORAGE_KEYS = ["enabled", "monitoredExtensions", "excludedSites",
                      "excludedAddresses", "bypassKey", "darkMode", "appSyncedAt"];

// Every sync starts a native host process, so the app is asked at most this
// often. The timestamp is persisted because Chrome's service worker and
// Firefox's event page lose memory between events; an in-memory timestamp would
// resync on nearly every download.
const APP_SYNC_TTL_MS = 30000;
// A decision waits this long for a due sync so edits made in the app apply to the
// very next download, without letting a slow host stall the browser.
const APP_SYNC_WAIT_MS = 1500;

function wildcardToRegex(pattern) {
    const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
    return new RegExp("^" + escaped + "$", "i");
}

// A bare domain ("example.com" or ".example.com") also covers its subdomains, which
// is what users expect from an exclusion list; wildcard patterns match literally.
function compileSitePattern(raw) {
    const pattern = raw.trim().toLowerCase();
    if (!pattern) return null;
    if (pattern.includes("*")) {
        const re = wildcardToRegex(pattern);
        return (host) => re.test(host);
    }
    const domain = pattern.replace(/^\.+/, "");
    return (host) => host === domain || host.endsWith("." + domain);
}

function compileAddressPattern(raw) {
    const pattern = raw.trim();
    if (!pattern) return null;
    const re = wildcardToRegex(pattern);
    return (url) => re.test(url);
}

// Storage is written from native-host responses; never assume element types.
function stringList(value, fallback) {
    return Array.isArray(value) ? value.filter((v) => typeof v === "string") : fallback;
}

// Mirrors AppSettings::withSiteExclusion(): a bare entry and its leading-dot form
// are the same site; wildcard patterns are the user's own and never touched.
function isEntryFor(entry, host) {
    return entry.trim().replace(/^\.+/, "").toLowerCase() === host;
}

function compile(stored) {
    const bypassKey = Number.isInteger(stored.bypassKey)
        && stored.bypassKey >= BYPASS_NONE && stored.bypassKey <= BYPASS_SHIFT
        ? stored.bypassKey : DEFAULT_BYPASS_KEY;
    const siteEntries = stringList(stored.excludedSites, DEFAULT_EXCLUDED_SITES);
    return {
        enabled: stored.enabled !== false,
        monitoredExtensions: new Set(stringList(stored.monitoredExtensions, DEFAULT_MONITORED_EXTENSIONS)
            .map((e) => e.trim().replace(/^\.+/, "").toLowerCase())
            .filter(Boolean)),
        excludedSiteEntries: siteEntries,
        excludedSites: siteEntries.map(compileSitePattern).filter(Boolean),
        excludedAddresses: stringList(stored.excludedAddresses, [])
            .map(compileAddressPattern).filter(Boolean),
        bypassKey,
        // null until the app has been reached once: the popup then follows the browser.
        darkMode: typeof stored.darkMode === "boolean" ? stored.darkMode : null,
        appSyncedAt: Number.isFinite(stored.appSyncedAt) ? stored.appSyncedAt : 0,
    };
}

let current = compile({});
let syncInFlight = null;
const reloadListeners = new Set();

async function reload() {
    current = compile(await ext.storage.local.get(STORAGE_KEYS));
    for (const listener of reloadListeners) listener(current);
}

// Called after every reload, i.e. once the new values are actually in effect.
// Reacting to storage.onChanged directly would race the reload and read stale
// values.
export function onSettingsReloaded(listener) {
    reloadListeners.add(listener);
}

// Background scripts are woken by the very event they must answer; decisions
// await this so a wake-up never runs on built-in defaults (e.g. ignoring an
// "Interception: OFF" the user set earlier).
const initialLoad = reload().catch((err) => {
    console.warn("[Stellar] Could not load settings:", err);
});

ext.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && STORAGE_KEYS.some((k) => k in changes))
        reload().catch(() => {});
});

export async function loadedSettings() {
    await initialLoad;
    return current;
}

// Settings for an interception decision: refreshed from the app when stale.
export async function decisionSettings() {
    await initialLoad;
    if (Date.now() - current.appSyncedAt >= APP_SYNC_TTL_MS) {
        let timer;
        await Promise.race([
            syncFromApp(),
            new Promise((resolve) => { timer = setTimeout(resolve, APP_SYNC_WAIT_MS); }),
        ]);
        clearTimeout(timer);
    }
    return current;
}

export function syncFromApp() {
    if (syncInFlight) return syncInFlight;
    syncInFlight = (async () => {
        // Stamp the attempt even when the app is unreachable so a missing host is
        // not respawned on every download.
        const update = { appSyncedAt: Date.now() };
        try {
            const resp = await nativeRequest({ type: "getSettings" }, 10000);
            if (resp?.type === "settings") {
                // Empty arrays are valid: the user may have cleared a list in the app.
                if (Array.isArray(resp.monitoredExtensions))
                    update.monitoredExtensions = stringList(resp.monitoredExtensions, []);
                if (Array.isArray(resp.excludedSites))
                    update.excludedSites = stringList(resp.excludedSites, []);
                if (Array.isArray(resp.excludedAddresses))
                    update.excludedAddresses = stringList(resp.excludedAddresses, []);
                if (Number.isInteger(resp.bypassInterceptKey))
                    update.bypassKey = resp.bypassInterceptKey;
                if (typeof resp.darkMode === "boolean")
                    update.darkMode = resp.darkMode;
            }
        } catch (err) {
            console.info("[Stellar] Could not sync settings from app:", err?.message ?? err);
        }
        try {
            await ext.storage.local.set(update);
            await reload();
        } catch (err) {
            console.warn("[Stellar] Could not store synced settings:", err);
        }
    })().finally(() => { syncInFlight = null; });
    return syncInFlight;
}

export async function setEnabled(enabled) {
    await ext.storage.local.set({ enabled: !!enabled });
    await reload();
}

export function isHostExcluded(host, settings) {
    const h = String(host || "").toLowerCase();
    return !!h && settings.excludedSites.some((match) => match(h));
}

// True when the site list holds an entry for exactly this host, i.e. one the
// extension can remove again without touching the user's wildcard patterns.
export function hasSiteEntry(host, settings) {
    return settings.excludedSiteEntries.some((entry) => isEntryFor(entry, host));
}

// Applies an exclusion the app has just acknowledged to the local copy, so it
// takes effect on the next download instead of after the next sync. The app
// stays the source of truth; the next sync returns the same list.
export async function mirrorSiteExclusion(host, exclude) {
    await initialLoad;
    const entries = current.excludedSiteEntries;
    const excludedSites = exclude
        ? (entries.some((e) => isEntryFor(e, host)) ? entries : [...entries, host])
        : entries.filter((e) => !isEntryFor(e, host));
    await ext.storage.local.set({ excludedSites, appSyncedAt: Date.now() });
    await reload();
}

export function isExcluded(url, settings) {
    let host;
    try { host = new URL(url).hostname.toLowerCase(); }
    catch { return true; }
    return isHostExcluded(host, settings)
        || settings.excludedAddresses.some((match) => match(url));
}
