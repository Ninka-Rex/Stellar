# Stellar Extension — Download Interception Decision Tree

This document describes every code path that can intercept a download and hand it off to the Stellar native host.

---

## Entry Points

There are **four** distinct entry points, each described below.

```
User action
    │
    ├─► [A] Direct link click (user clicks <a href="...">)
    │       Handled by: content.js click listener (capture phase)
    │
    ├─► [B] Programmatic click (JS calls element.click() / dispatchEvent)
    │       Handled by: page-injected script overrides in content.js
    │
    ├─► [C] Browser-initiated download (webRequest / downloads.onCreated)
    │       Chrome: chrome.downloads.onCreated
    │       Firefox: browser.webRequest.onHeadersReceived (blocking)
    │
    └─► [D] User right-clicks and selects "Download with Stellar"
            Handled by: service-worker contextMenus.onClicked
```

---

## [A] Direct Link Click

```
document click event (capture phase)
    │
    ├─ e.defaultPrevented? → YES → ignore (something else handled it)
    │
    ├─ e.button !== 0? → YES → ignore (not left-click)
    │
    ├─ target.closest("a") found?
    │       NO → ignore
    │
    ├─ Modifier key held? (Alt/Ctrl/Shift)
    │       YES → send recordModifierKey to SW → return
    │             (modifier key state stored with 10 s TTL so
    │              the subsequent downloads.onCreated / webRequest
    │              event can read and bypass interception)
    │
    ├─ shouldPreIntercept(anchor, href)?
    │   │
    │   ├─ anchor has [download] attribute? → YES → intercept
    │   │
    │   ├─ href starts with http/https/ftp? → NO → ignore
    │   │
    │   └─ isForceInterceptHost(href)?
    │       (Google Drive / Drive usercontent with download signal)
    │           YES → intercept
    │           NO  → ignore
    │
    ├─ e.preventDefault() + e.stopPropagation()
    │
    └─► tryInterceptUrl(href, filename, explicitIntent)
            │
            ├─ href is blob:?
            │       YES → resolveBlobSourceUrl()
            │               send resolveBlobRequest postMessage
            │               page script looks up blobUrlMap
            │               returns real HTTP source URL (250 ms timeout)
            │               resolved? → use real URL
            │               not resolved? → abort (return false)
            │
            └─► chrome/browser.runtime.sendMessage({ type: "interceptLinkClick", ... })
                    (retry once after 120 ms on cold-start failure)
                        │
                        Service Worker: interceptLinkClick handler
                            │
                            ├─ forceIntercept(url)? → YES → proceed
                            │
                            ├─ shouldIntercept(url, mime, filename, explicitIntent)?
                            │   (see Interception Decision below)
                            │       NO → sendResponse({ ok: false })
                            │
                            ├─ collectCookies(url)
                            │
                            └─► requestDownload → native host
                                    ok? → sendResponse({ ok: true })
                                    fail? → sendResponse({ ok: false })

        handleBack (content.js):
            resp.ok? → done
            !resp.ok && !explicitIntent → window.location.href = href (browser handles it)
```

---

## [B] Programmatic Click (JS-initiated, Firefox + Chrome)

The content script injects a `<script>` tag into the page context to patch native APIs before any page script runs.

```
Page script calls anchor.click() or anchor.dispatchEvent(click)
    │
    Patched HTMLAnchorElement.prototype.click / dispatchEvent
        │
        ├─ __stellarBypassClick flag set?
        │       YES → call original (Stellar told us to let it through)
        │
        ├─ anchor has [download] + href?
        │       NO → call original
        │
        └─ postMessage({ __stellarType: "programmaticDownloadIntent", reqId, href, filename })
                │
                Content script window.addEventListener("message")
                    │
                    └─► tryInterceptUrl(href, filename, explicitIntent=true)
                            (same path as [A] above)
                            │
                            postMessage({ __stellarType: "programmaticDownloadAck", reqId, handled })
                                │
                                Page script receives ack:
                                    handled=true  → done (Stellar owns it)
                                    handled=false → __stellarBypassClick=true; origClick()
                                    timeout (5 s) → timeout: do nothing (Stellar owns it)

Page script calls window.open("blob:...")
    │
    Patched window.open
        │
        ├─ URL is blob:? → NO → call original
        │
        └─ postMessage({ __stellarType: "programmaticDownloadIntent", reqId, href, filename:"" })
                └─► same path as anchor.click() above
```

---

## [C] Browser-Initiated Download

### Chrome: `chrome.downloads.onCreated`

```
chrome.downloads.onCreated fires
    │
    handleDownloadCreated({ url, filename, referrer, mime })
        │
        ├─ Modifier key active (within 10 s window)?
        │       YES → consume key, return (let browser handle)
        │
        ├─ forceIntercept(url)?  → YES → proceed to cancel+redirect
        │
        ├─ shouldIntercept(url, mime, filename)?
        │   (see Interception Decision below)
        │       NO → return (browser keeps the download)
        │
        ├─ chrome.downloads.cancel(item.id)
        ├─ chrome.downloads.erase({ id })
        │
        ├─ Get active tab URL (for pageUrl / referrer)
        │
        ├─ collectCookies(url) — url + parent domains
        │
        └─► requestDownload → native host
                fail? → chrome.tabs.create({ url })  (browser fallback)
```

### Firefox: `browser.webRequest.onHeadersReceived` (blocking)

Firefox can cancel the request at the network layer — before any browser download UI appears.

```
browser.webRequest.onHeadersReceived fires
    │
    ├─ Request type in { xmlhttprequest, beacon, ping, csp_report, websocket }?
    │       YES → return {} (non-download traffic, never intercept)
    │
    ├─ Modifier key active?
    │       YES → consume key, return {} (let browser handle)
    │
    ├─ Parse Content-Type and Content-Disposition headers
    │   Extract filenameHint from Content-Disposition (RFC 5987 preferred)
    │   isAttachment = Content-Disposition starts with "attachment"
    │
    ├─ forceIntercept(url)?  → YES → proceed
    │
    ├─ shouldInterceptSync(url, contentType, filenameHint, isAttachment)?
    │   (synchronous version using liveSettings — no await needed here)
    │       NO → return {}
    │
    ├─ return { cancel: true }  ← network request is aborted here
    │
    └─► setTimeout(0) async callback:
            ├─ collectCookies(url)
            └─► requestDownload → native host
                    fail? → console.error (no browser fallback — request already cancelled)
```

---

## [D] Context Menu

```
User right-clicks → "Download with Stellar"
    │
    contextMenus.onClicked({ linkUrl, srcUrl, pageUrl })
        │
        ├─ url = linkUrl || srcUrl || pageUrl
        │
        ├─ collectCookies(url)
        │
        └─► requestDownload → native host
                fail? → console.error
```

No interception check — context menu is always explicit user intent.

---

## Interception Decision (`shouldIntercept`)

Called from paths [A] and [C]-Chrome. Firefox [C] uses `shouldInterceptSync` which is identical logic but reads from `liveSettings` (already in memory) instead of async storage.

```
shouldIntercept(url, mimeType, filenameHint, explicitIntent)
    │
    ├─ url is data: or blob:? → NO (already resolved by content script)
    │
    ├─ url scheme not http/https/ftp? → NO
    │
    ├─ isApiRpcRequest(url, filenameHint, mimeType)?
    │   │
    │   ├─ Path has real file extension (not js/json/html/css/...)? → NOT API → false
    │   │
    │   ├─ Path matches /api/, /graphql/, /rpc/, /ajax/, /batchexecute/, /_/?
    │   │   AND no explicit download signal (no /download/, ?download, ?attachment,
    │   │       ?export=download, ?alt=media, ?response-content-disposition)?
    │   │   AND (no path ext OR filename is response.bin OR MIME is JSON/text/JS)?
    │   │       → YES (is API) → NO intercept
    │   │
    │   ├─ GTM analytics beacon (/td with ?gtm or ?id=gtm-...)? → YES → NO intercept
    │   │
    │   └─ ?rpcids + ?rt=c (Google batchexecute RPC)? → YES → NO intercept
    │
    ├─ settings.enabled? → NO → NO intercept
    │
    ├─ host matches any excludedSites pattern? → YES → NO intercept
    │
    ├─ url matches any excludedAddresses pattern? → YES → NO intercept
    │
    ├─ mimeType is text/html, text/css, application/javascript,
    │     image/svg, image/gif, image/png, image/jpeg, image/webp?
    │       YES → NO intercept (inline page resource)
    │
    ├─ Determine file extension:
    │   1. From URL pathname
    │   2. Fallback: from filenameHint
    │
    ├─ Extension found?
    │   │
    │   YES:
    │   ├─ Extension is media (mp3/mp4/mkv/avi/mov/...)
    │   │   AND NOT explicitIntent?
    │   │       → NO intercept (streaming playback link, not a download)
    │   │
    │   └─ monitoredExtensions.has(ext)?
    │           YES → INTERCEPT
    │           NO  → NO intercept
    │
    └─ No extension:
        ├─ explicitIntent? → YES → INTERCEPT (blob-resolved URL, trust the click)
        │
        └─ mimeType present?
            │
            ├─ Known MIME → mapped extension → monitoredExtensions.has(mappedExt)?
            │
            ├─ video/* → any video ext in monitoredExtensions? → INTERCEPT / NO
            │
            ├─ audio/* → any audio ext in monitoredExtensions? → INTERCEPT / NO
            │
            └─ application/octet-stream or unknown → NO intercept
```

---

## Force Intercept (`forceIntercept`)

Short-circuits the full interception decision for Google Drive / Docs download URLs regardless of monitored extensions.

```
forceIntercept(url)
    │
    ├─ host is drive.usercontent.google.com or *.drive.usercontent.google.com? → isDriveUserContent
    ├─ host is drive.google.com, *.drive.google.com,
    │              docs.google.com, *.docs.google.com?  → isGoogleDocHost
    │
    ├─ Neither? → false
    │
    ├─ path is /uc or starts with /download or contains /download/? → true
    ├─ ?export=download? → true
    ├─ ?response-content-disposition? → true
    ├─ isDriveUserContent AND ?id? → true
    └─ otherwise → false
```

---

## Blob Resolver Bridge

The page-injected script tracks blob URLs back to their network origin so the service worker can download the real HTTP URL instead of a local `blob:` reference.

```
page script calls fetch(url)
    → patched fetch wraps resp.blob() / resp.arrayBuffer()
    → on .blob() call: blobMeta.set(blob, { url: resp.url, mime: contentType })
    → on .arrayBuffer() call: bufferMeta.set(ab, { url: resp.url, mime: contentType })

page script calls XHR with responseType="blob"
    → patched open() records URL in xhrUrlMap
    → patched send() listens for loadend:
        → blobMeta.set(this.response, { url, mime: blob.type })

page script calls new Blob([...parts])
    → StellarBlob constructor checks each part for bufferMeta / blobMeta
    → if found: propagates { url, mime } to the new blob

page script calls URL.createObjectURL(blob)
    → patched createObjectURL looks up blobMeta
    → if found: blobUrlMap.set(blobUrl, { url, mime })

content script needs to resolve blob:...
    → postMessage({ __stellarType: "resolveBlobRequest", reqId, blobUrl })
    → page script message handler looks up blobUrlMap
    → postMessage({ __stellarType: "resolveBlobResponse", reqId, sourceUrl, mime })
    → content script resolves with sourceUrl (250 ms timeout if not found)
```

---

## Modifier Key Bypass

Allows the user to hold a modifier key during a click to let the browser handle the download natively (e.g. open in-browser PDF viewer with Ctrl+click).

```
content.js click handler detects modifier (Alt/Ctrl/Shift)
    → sendMessage({ type: "recordModifierKey", modifierKey: 1|2|3 })
    → service worker stores { lastModifierKey, lastModifierKeyTime }
    → 10 second TTL (auto-cleared by setTimeout)

Next download event (downloads.onCreated / webRequest.onHeadersReceived):
    → getAndClearModifierKey()
        TTL expired? → return 0
        else → return key, reset to 0 (consume it)
    → key > 0? → bypass all interception
```

---

## Settings Cache

```
getSettings()
    │
    ├─ cachedSettings valid (< 5 s old)? → return cache
    │
    ├─ syncSettingsFromApp()
    │   → sendNativeMessage({ type: "getSettings" })
    │   → app returns { monitoredExtensions[], excludedSites[], excludedAddresses[] }
    │   → write to chrome/browser.storage.local
    │   → cachedSettings = null (force re-read below)
    │
    └─ chrome/browser.storage.local.get(...)
        → build cachedSettings from stored values
        → fallback to DEFAULT_* if not stored
        → set cachedSettingsTime = now

chrome/browser.storage.onChanged:
    → cachedSettings = null (force re-read on next request)
```
