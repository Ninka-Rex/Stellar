// Stellar Download Manager — Cookie header collection
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

// Fallback for when no real request was observed (context menu, link lists).
// When a request was observed, its actual Cookie header is used instead, since
// that is exactly what the browser sent.
//
// getAll({url}) already applies the browser's own matching: domain cookies of
// parent domains are included, while host-only and __Host- cookies of a parent
// domain are not. Querying parent domains separately would hand those cookies to
// a subdomain the browser deliberately withholds them from.
export async function cookieHeaderFor(url, storeId) {
    const query = { url };
    if (storeId) query.storeId = storeId;
    let list;
    try {
        list = await ext.cookies.getAll(query);
    } catch {
        // Firefox with First-Party Isolation rejects queries that omit
        // firstPartyDomain; null asks for every isolation key.
        try { list = await ext.cookies.getAll({ ...query, firstPartyDomain: null }); }
        catch { return ""; }
    }
    // RFC 6265 §5.4: longer paths first. Servers that read the first of two
    // same-named cookies rely on the browser's ordering.
    list.sort((a, b) => b.path.length - a.path.length);
    return list.map((c) => `${c.name}=${c.value}`).join("; ");
}

// The cookie store (container / private / incognito) a tab uses, so a download
// from a container or private tab is fetched with that session and not the
// default one.
export async function cookieStoreForTab(tabId) {
    if (!Number.isInteger(tabId) || tabId < 0) return undefined;
    try {
        const tab = await ext.tabs.get(tabId);
        if (tab?.cookieStoreId) return tab.cookieStoreId; // Firefox
    } catch {
        return undefined;
    }
    try {
        const stores = await ext.cookies.getAllCookieStores();
        return stores.find((s) => s.tabIds.includes(tabId))?.id;
    } catch {
        return undefined;
    }
}
