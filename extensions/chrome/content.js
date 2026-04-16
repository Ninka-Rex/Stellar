// content.js – injected into all pages
// Tracks modifier keys and pre-intercepts likely download links so Chrome
// doesn't open its native downloads tray before Stellar handoff.

function isForceInterceptHost(url) {
    try {
        const u = new URL(url);
        const host = u.hostname.toLowerCase();
        const path = u.pathname.toLowerCase();
        const isDriveUserContent = host === "drive.usercontent.google.com"
            || host.endsWith(".drive.usercontent.google.com");
        const isGoogleDocHost = host === "drive.google.com"
            || host.endsWith(".drive.google.com")
            || host === "docs.google.com"
            || host.endsWith(".docs.google.com");
        if (!isDriveUserContent && !isGoogleDocHost) return false;
        if (path === "/uc" || path.startsWith("/download") || path.includes("/download/")) return true;
        if (u.searchParams.get("export") === "download") return true;
        if (u.searchParams.has("response-content-disposition")) return true;
        if (isDriveUserContent && u.searchParams.has("id")) return true;
        return false;
    } catch {
        return false;
    }
}

function shouldPreIntercept(anchor, href) {
    if (!href) return false;
    // Click-time interception is now explicit-intent only; otherwise media links
    // (e.g. in-page MP3 playback) can be hijacked before playback starts.
    if (anchor.hasAttribute("download")) return true;
    if (!href.startsWith("http://") && !href.startsWith("https://") && !href.startsWith("ftp://"))
        return false;
    if (isForceInterceptHost(href)) return true;
    return false;
}

function installBlobResolverBridge() {
    if (window.__stellarBlobBridgeInstalled) return;
    window.__stellarBlobBridgeInstalled = true;

    const script = document.createElement("script");
    script.textContent = `
(() => {
    if (window.__stellarPageBlobResolverInstalled) return;
    window.__stellarPageBlobResolverInstalled = true;

    const blobMeta = new WeakMap();
    const bufferMeta = new WeakMap();
    const blobUrlMap = new Map();
    const pendingProgrammatic = new Map();
    const maxEntries = 2000;

    function rememberBlobUrl(blobUrl, meta) {
        if (!blobUrl || !meta || !meta.url) return;
        blobUrlMap.set(blobUrl, { url: String(meta.url), mime: String(meta.mime || "") });
        if (blobUrlMap.size > maxEntries) {
            const firstKey = blobUrlMap.keys().next().value;
            if (firstKey) blobUrlMap.delete(firstKey);
        }
    }

    const origFetch = window.fetch;
    if (typeof origFetch === "function") {
        window.fetch = async function(...args) {
            const resp = await origFetch.apply(this, args);
            try {
                const respUrl = resp.url || "";
                const respType = (resp.headers && resp.headers.get("content-type")) || "";
                const origBlob = resp.blob ? resp.blob.bind(resp) : null;
                const origArrayBuffer = resp.arrayBuffer ? resp.arrayBuffer.bind(resp) : null;
                if (origBlob) {
                    resp.blob = async function() {
                        const b = await origBlob();
                        try { blobMeta.set(b, { url: respUrl, mime: respType || b.type || "" }); } catch {}
                        return b;
                    };
                }
                if (origArrayBuffer) {
                    resp.arrayBuffer = async function() {
                        const ab = await origArrayBuffer();
                        try { bufferMeta.set(ab, { url: respUrl, mime: respType || "" }); } catch {}
                        return ab;
                    };
                }
            } catch {}
            return resp;
        };
    }

    const xhrUrlMap = new WeakMap();
    const origXhrOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        try { xhrUrlMap.set(this, String(url || "")); } catch {}
        return origXhrOpen.call(this, method, url, ...rest);
    };
    const origXhrSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(...args) {
        try {
            this.addEventListener("loadend", () => {
                try {
                    if (this.responseType !== "blob") return;
                    const b = this.response;
                    if (!(b instanceof Blob)) return;
                    const u = xhrUrlMap.get(this) || this.responseURL || "";
                    if (!u) return;
                    blobMeta.set(b, { url: u, mime: b.type || "" });
                } catch {}
            }, { once: true });
        } catch {}
        return origXhrSend.apply(this, args);
    };

    const origCreateObjectURL = URL.createObjectURL.bind(URL);
    URL.createObjectURL = function(obj) {
        const blobUrl = origCreateObjectURL(obj);
        try {
            const meta = blobMeta.get(obj);
            if (meta) rememberBlobUrl(blobUrl, meta);
        } catch {}
        return blobUrl;
    };

    const NativeBlob = Blob;
    function findMetaInBlobParts(parts) {
        try {
            if (!Array.isArray(parts)) return null;
            for (const part of parts) {
                if (!part) continue;
                if (part instanceof ArrayBuffer) {
                    const m = bufferMeta.get(part);
                    if (m && m.url) return m;
                    continue;
                }
                if (ArrayBuffer.isView(part)) {
                    const m = bufferMeta.get(part.buffer);
                    if (m && m.url) return m;
                }
            }
        } catch {}
        return null;
    }
    class StellarBlob extends NativeBlob {
        constructor(parts = [], options = {}) {
            super(parts, options);
            try {
                const m = findMetaInBlobParts(parts);
                if (m) blobMeta.set(this, { url: String(m.url || ""), mime: String(m.mime || this.type || "") });
            } catch {}
        }
    }
    window.Blob = StellarBlob;

    const origAnchorClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function(...args) {
        try {
            if (this.__stellarBypassClick) {
                this.__stellarBypassClick = false;
                return origAnchorClick.apply(this, args);
            }
            const href = String(this.href || this.getAttribute("href") || "");
            if (href && this.hasAttribute("download")) {
                const filename = String(this.getAttribute("download") || "");
                const reqId = "stellar-prog-" + Date.now() + "-" + Math.random().toString(36).slice(2);
                const timer = setTimeout(() => {
                    const p = pendingProgrammatic.get(reqId);
                    if (!p) return;
                    pendingProgrammatic.delete(reqId);
                }, 5000);
                pendingProgrammatic.set(reqId, { anchor: this, timer });
                window.postMessage({ __stellarType: "programmaticDownloadIntent", reqId, href, filename }, "*");
                return;
            }
        } catch {}
        return origAnchorClick.apply(this, args);
    };

    const origAnchorDispatchEvent = HTMLAnchorElement.prototype.dispatchEvent;
    HTMLAnchorElement.prototype.dispatchEvent = function(ev) {
        try {
            if (this.__stellarBypassClick)
                return origAnchorDispatchEvent.call(this, ev);
            const isClick = ev && ev.type === "click";
            const href = String(this.href || this.getAttribute("href") || "");
            if (isClick && href && this.hasAttribute("download")) {
                const filename = String(this.getAttribute("download") || "");
                const reqId = "stellar-prog-" + Date.now() + "-" + Math.random().toString(36).slice(2);
                const timer = setTimeout(() => {
                    const p = pendingProgrammatic.get(reqId);
                    if (!p) return;
                    pendingProgrammatic.delete(reqId);
                }, 5000);
                pendingProgrammatic.set(reqId, { anchor: this, timer });
                window.postMessage({ __stellarType: "programmaticDownloadIntent", reqId, href, filename }, "*");
                return true;
            }
        } catch {}
        return origAnchorDispatchEvent.call(this, ev);
    };

    const origWindowOpen = window.open;
    if (typeof origWindowOpen === "function") {
        window.open = function(url, ...rest) {
            try {
                const href = String(url || "");
                if (href.startsWith("blob:")) {
                    const reqId = "stellar-prog-" + Date.now() + "-" + Math.random().toString(36).slice(2);
                    const timer = setTimeout(() => { pendingProgrammatic.delete(reqId); }, 5000);
                    pendingProgrammatic.set(reqId, { anchor: null, timer });
                    window.postMessage({ __stellarType: "programmaticDownloadIntent", reqId, href, filename: "" }, "*");
                    return null;
                }
            } catch {}
            return origWindowOpen.call(this, url, ...rest);
        };
    }

    window.addEventListener("message", (ev) => {
        const msg = ev.data;
        if (msg && msg.__stellarType === "programmaticDownloadAck") {
            const p = pendingProgrammatic.get(msg.reqId);
            if (!p) return;
            pendingProgrammatic.delete(msg.reqId);
            clearTimeout(p.timer);
            if (!msg.handled && p.anchor) {
                try {
                    p.anchor.__stellarBypassClick = true;
                    origAnchorClick.call(p.anchor);
                } catch {}
            }
            return;
        }
        if (!msg || msg.__stellarType !== "resolveBlobRequest") return;
        const blobUrl = String(msg.blobUrl || "");
        const mapping = blobUrlMap.get(blobUrl) || null;
        window.postMessage({
            __stellarType: "resolveBlobResponse",
            reqId: msg.reqId,
            blobUrl,
            sourceUrl: mapping ? mapping.url : "",
            mime: mapping ? mapping.mime : ""
        }, "*");
    });
})();
`;
    (document.documentElement || document.head || document.body).appendChild(script);
    script.remove();
}

function resolveBlobSourceUrl(blobUrl) {
    return new Promise((resolve) => {
        try {
            installBlobResolverBridge();
            const reqId = "stellar-" + Date.now() + "-" + Math.random().toString(36).slice(2);
            let done = false;
            const timer = setTimeout(() => {
                if (!done) {
                    done = true;
                    window.removeEventListener("message", onMessage);
                    resolve("");
                }
            }, 250);
            function onMessage(ev) {
                const msg = ev.data;
                if (!msg || msg.__stellarType !== "resolveBlobResponse" || msg.reqId !== reqId) return;
                if (done) return;
                done = true;
                clearTimeout(timer);
                window.removeEventListener("message", onMessage);
                resolve(typeof msg.sourceUrl === "string" ? msg.sourceUrl : "");
            }
            window.addEventListener("message", onMessage);
            window.postMessage({ __stellarType: "resolveBlobRequest", reqId, blobUrl }, "*");
        } catch {
            resolve("");
        }
    });
}

// Install early so programmatic download clicks (no direct user anchor click)
// are intercepted even before any blob URL resolution request occurs.
installBlobResolverBridge();

async function tryInterceptUrl(url, filename, explicitIntent) {
    const href = String(url || "");
    if (!href) return false;
    let requestUrl = href;
    if (href.startsWith("blob:")) {
        const resolved = await resolveBlobSourceUrl(href);
        if (resolved && (resolved.startsWith("http://") || resolved.startsWith("https://")))
            requestUrl = resolved;
        else
            return false;
    }
    const payload = {
        type: "interceptLinkClick",
        url: requestUrl,
        filename: filename || "",
        explicitIntent: !!explicitIntent,
        pageUrl: location.href,
        referrer: document.referrer || location.href,
        cookies: "",
        modifierKey: 0,
    };
    try {
        let resp = await chrome.runtime.sendMessage(payload);
        if (resp?.ok) return true;
        // Retry once to tolerate service worker cold-start wake latency.
        await new Promise((r) => setTimeout(r, 120));
        resp = await chrome.runtime.sendMessage(payload);
        return !!resp?.ok;
    } catch {
        return false;
    }
}

window.addEventListener("message", (ev) => {
    const msg = ev.data;
    if (!msg || msg.__stellarType !== "programmaticDownloadIntent") return;
    const reqId = String(msg.reqId || "");
    if (!reqId) return;
    (async () => {
        const handled = await tryInterceptUrl(String(msg.href || ""), String(msg.filename || ""), true);
        window.postMessage({ __stellarType: "programmaticDownloadAck", reqId, handled }, "*");
    })();
});

document.addEventListener("click", async (e) => {
    if (e.defaultPrevented) return;
    if (e.button !== 0) return;
    const target = e.target.closest("a");
    if (!target || !target.href) return;

    // Determine which modifier key is held (0=none, 1=alt, 2=ctrl, 3=shift)
    let modifierKey = 0;
    if (e.altKey) modifierKey = 1;
    else if (e.ctrlKey) modifierKey = 2;
    else if (e.shiftKey) modifierKey = 3;

    // Only notify if a modifier key was held
    if (modifierKey > 0) {
        chrome.runtime.sendMessage({
            type: "recordModifierKey",
            modifierKey: modifierKey,
        }).catch(() => {
            // Service worker may not be ready, ignore
        });
        return;
    }

    if (!shouldPreIntercept(target, target.href)) return;
    const explicitIntent = target.hasAttribute("download");

    e.preventDefault();
    e.stopPropagation();

    const href = target.href;
    const handled = await tryInterceptUrl(href, target.getAttribute("download") || "", explicitIntent);
    if (!handled && !explicitIntent) window.location.href = href;
}, true);  // capture phase
