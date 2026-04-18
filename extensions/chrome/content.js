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
    script.src = chrome.runtime.getURL("page-bridge.js");
    script.async = false;
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
