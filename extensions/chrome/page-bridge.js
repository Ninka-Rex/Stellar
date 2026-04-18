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
