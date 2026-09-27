// Stellar Download Manager — Interception decision
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

// Pure functions only (no browser APIs) so both browsers' background scripts
// share one decision and cannot drift apart again.

import { isExcluded, isHostExcluded } from "./settings.js";

const TRANSFER_SCHEMES = new Set(["http:", "https:", "ftp:"]);

// Audio/video that a browser plays inline. Without an explicit download signal a
// link to one of these is playback, not a download.
const MEDIA_EXTS = new Set([
    "mp3","m4a","aac","ogg","oga","opus","wav","wma","flac","aif","ra","mpa",
    "mp4","m4v","mkv","avi","mov","wmv","webm","mpeg","mpg","3gp","ogv","rm","rmvb","asf","qt","flv",
]);
const VIDEO_EXTS = ["mp4","mkv","avi","mov","wmv","flv","webm","m4v","mpg","mpeg","3gp","ogv","rm","rmvb","asf","qt"];
const AUDIO_EXTS = ["mp3","aac","wav","flac","ogg","m4a","wma","ra","aif","mpa"];

// Used when neither the filename nor the URL carries an extension.
const MIME_TO_EXT = {
    "application/pdf": "pdf",
    "application/zip": "zip",
    "application/x-zip": "zip",
    "application/x-zip-compressed": "zip",
    "application/x-rar": "rar",
    "application/x-rar-compressed": "rar",
    "application/vnd.rar": "rar",
    "application/x-7z-compressed": "7z",
    "application/x-tar": "tar",
    "application/gzip": "gz",
    "application/x-gzip": "gz",
    "application/x-bzip2": "bz2",
    "application/x-xz": "xz",
    "application/x-msdownload": "exe",
    "application/x-msdos-program": "exe",
    "application/x-dosexec": "exe",
    "application/x-msi": "msi",
    "application/x-iso9660-image": "iso",
    "application/vnd.android.package-archive": "apk",
    "application/x-bittorrent": "torrent",
    "application/vnd.ms-powerpoint": "ppt",
    "video/mp4": "mp4",
    "video/x-matroska": "mkv",
    "video/x-msvideo": "avi",
    "video/quicktime": "mov",
    "video/x-ms-wmv": "wmv",
    "video/webm": "webm",
    "video/mpeg": "mpg",
    "video/3gpp": "3gp",
    "video/x-flv": "flv",
    "audio/mpeg": "mp3",
    "audio/mp4": "m4a",
    "audio/ogg": "ogg",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/x-ms-wma": "wma",
    "audio/aac": "aac",
    "audio/flac": "flac",
    "image/tiff": "tif",
};

// Responses that make up web pages. Taking one of these without an explicit
// download signal hijacks ordinary browsing (e.g. an HTML page under /download/).
const PAGE_MIMES = new Set([
    "text/html", "application/xhtml+xml", "text/css", "text/javascript",
    "application/javascript", "application/x-javascript", "application/json",
    "image/svg+xml", "image/gif", "image/png", "image/jpeg", "image/webp", "image/avif",
]);

// Extensions that mark a script or page endpoint rather than a downloadable file.
const ENDPOINT_EXTS = new Set(["js","json","html","htm","css","xml","svg","map","ts","jsx","tsx",
                               "wasm","php","aspx","asp","jsp","cgi"]);

// Types Firefox renders in a tab. A top-level response of any other type turns
// into a browser download, which is ground truth that the user is downloading.
function isBrowserRenderable(mime) {
    if (!mime) return true; // the browser sniffs; assume it may render
    if (mime.startsWith("text/") || mime.startsWith("image/")
        || mime.startsWith("video/") || mime.startsWith("audio/"))
        return true;
    return mime === "application/pdf" || mime === "application/json"
        || mime === "application/xml" || mime === "application/xhtml+xml"
        || mime === "application/javascript" || mime === "application/x-javascript"
        || mime === "application/ecmascript" || mime === "application/rss+xml"
        || mime === "application/atom+xml";
}

export function parseUrl(url) {
    try { return new URL(url); } catch { return null; }
}

export function isTransferableUrl(url) {
    const u = typeof url === "string" ? parseUrl(url) : null;
    return !!u && TRANSFER_SCHEMES.has(u.protocol);
}

// URLs the app may be handed from a context menu: transferable URLs plus magnets.
export function isSendableUrl(url) {
    return isTransferableUrl(url) || (typeof url === "string" && /^magnet:\?/i.test(url));
}

export function mimeEssence(contentType) {
    return String(contentType || "").split(";")[0].trim().toLowerCase();
}

// Last path component with any directory part removed. Server-supplied names can
// contain "/" or "\"; the app sanitizes too, but nothing here should treat a
// traversal string as a name.
export function baseName(name) {
    const parts = String(name || "").split(/[\\/]/);
    return (parts.pop() || "").trim();
}

export function extensionOf(name) {
    const base = baseName(name);
    const dot = base.lastIndexOf(".");
    if (dot < 0) return "";
    const ext = base.slice(dot + 1).toLowerCase();
    return /^[a-z0-9]{1,10}$/.test(ext) ? ext : "";
}

function urlFileName(u) {
    const seg = u.pathname.split("/").pop() || "";
    try { return decodeURIComponent(seg); } catch { return seg; }
}

function hasDlParamIntent(sp) {
    const v = (sp.get("dl") || "").toLowerCase();
    return v === "1" || v === "true" || v === "yes" || v === "download";
}

// Query parameters cloud hosts use to ask for a download (Drive "export=download",
// Dropbox "dl=1", S3 "response-content-disposition", ...). Unambiguous on their own.
function hasQueryDownloadSignal(u) {
    const sp = u.searchParams;
    return sp.get("export") === "download"
        || sp.get("alt") === "media"
        || sp.has("response-content-disposition")
        || sp.has("attachment")
        || sp.has("filename")
        || sp.has("download")
        || hasDlParamIntent(sp);
}

// Path shapes of extensionless cloud downloads ("/s/<id>/download", Drive "/uc").
// Ambiguous alone — plenty of HTML pages live under /download — so trusted only
// once the response itself says "file".
function hasPathDownloadSignal(u) {
    const path = u.pathname.toLowerCase();
    return path === "/uc" || path.endsWith("/download") || path.includes("/download/");
}

function isApiRpcRequest(u, filename, mime) {
    const host = u.hostname.toLowerCase();
    const path = u.pathname.toLowerCase();
    const sp = u.searchParams;
    const fn = filename.toLowerCase();

    // Analytics beacons (Google Tag Manager "/td").
    if ((path.endsWith("/td") || path.includes("/td/"))
        && (sp.has("gtm") || /^gtm-/i.test(sp.get("id") || "")))
        return true;
    // Google RPC channels (Gemini, Docs, ...).
    if (sp.has("rpcids") && sp.get("rt") === "c") return true;
    if ((host === "google.com" || host.endsWith(".google.com")) && path.includes("/data/batchexecute"))
        return true;
    // YouTube web-app asset buckets.
    if ((host === "youtube.com" || host.endsWith(".youtube.com"))
        && (path.startsWith("/s/") || path.startsWith("/yts/")))
        return true;

    // A real file extension outranks an /api/ segment (e.g. /api/files/report.pdf).
    const pathExt = extensionOf(urlFileName(u));
    if (pathExt && !ENDPOINT_EXTS.has(pathExt)) return false;

    const textual = mime.startsWith("application/json") || mime.startsWith("text/plain")
        || mime.startsWith("text/javascript");
    const genericName = fn === "response.bin" || fn === "response";
    const apiPath = /(?:^|\/)(api|graphql|rpc|ajax|batchexecute)(?:\/|$)/.test(path) || path.includes("/_/");
    const explicit = hasQueryDownloadSignal(u) || path.includes("/download/");

    if (apiPath && !explicit && (!pathExt || genericName || textual)) return true;
    if (genericName && (path.includes("/api/") || textual)) return true;
    return false;
}

// CloudFront/AWS-signed playback URLs (e.g. Streamable). The path looks like a
// media file but it is a short-lived player token; taking it breaks playback.
function isSignedMediaPlaybackUrl(u) {
    const sp = u.searchParams;
    const signed = sp.has("Expires") && sp.has("Signature")
        && (sp.has("Key-Pair-Id") || sp.has("KeyPair-Id") || sp.has("AWSAccessKeyId"));
    return signed && /\.(mp4|m4v|mkv|webm|mov|avi|wmv|flv|mp3|m4a|aac|ogg|wav|flac|m3u8|ts)$/i.test(u.pathname);
}

// RFC 6266 Content-Disposition with RFC 8187 extended parameters. Quoted values
// may contain ";", so the header is tokenized rather than split.
export function parseContentDisposition(value) {
    const result = { attachment: false, filename: "" };
    const header = String(value || "");
    if (!header) return result;

    let i = 0;
    const readUntil = (stop) => {
        const start = i;
        while (i < header.length && !stop.includes(header[i])) i++;
        return header.slice(start, i).trim();
    };
    result.attachment = readUntil(";").toLowerCase() === "attachment";

    let plain = "";
    let extended = "";
    while (i < header.length) {
        i++; // skip ";"
        const name = readUntil("=;").toLowerCase();
        if (header[i] !== "=") continue;
        i++;
        while (header[i] === " " || header[i] === "\t") i++;
        let val = "";
        if (header[i] === '"') {
            i++;
            while (i < header.length && header[i] !== '"') {
                if (header[i] === "\\" && i + 1 < header.length) i++;
                val += header[i++];
            }
            i++;
            readUntil(";");
        } else {
            val = readUntil(";");
        }
        if (name === "filename*" && !extended) {
            const m = /^([^']*)'[^']*'(.*)$/.exec(val);
            if (m) {
                const charset = m[1].toLowerCase();
                try {
                    if (charset === "utf-8") extended = decodeURIComponent(m[2]);
                    else if (charset === "iso-8859-1")
                        extended = m[2].replace(/%([0-9a-f]{2})/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
                } catch { /* malformed escape: fall back to the plain parameter */ }
            }
        } else if (name === "filename" && !plain) {
            plain = val;
        }
    }
    result.filename = baseName(extended || plain);
    return result;
}

// c.url            — URL the response/download came from (after redirects)
// c.originalUrl    — URL before redirects, if different
// c.mime           — response Content-Type
// c.filename       — server- or page-suggested filename
// c.attachment     — Content-Disposition: attachment
// c.userIntent     — the user clicked a link carrying the `download` attribute
// c.browserDownload— the browser itself is saving this response as a file
// c.pageUrl        — page the download started from, if known
export function shouldIntercept(c, settings) {
    const u = parseUrl(c.url);
    if (!u || !TRANSFER_SCHEMES.has(u.protocol)) return false;
    if (!settings.enabled) return false;
    if (isExcluded(c.url, settings)) return false;
    if (c.originalUrl && c.originalUrl !== c.url && isExcluded(c.originalUrl, settings)) return false;
    // The site list also applies to the page the download starts from: files of
    // an excluded site are usually served from other hosts (CDNs, storage).
    const page = c.pageUrl ? parseUrl(c.pageUrl) : null;
    if (page && (page.protocol === "http:" || page.protocol === "https:")
        && isHostExcluded(page.hostname, settings))
        return false;

    const mime = mimeEssence(c.mime);
    const filename = baseName(c.filename);
    const userIntent = !!c.userIntent;
    const attachment = !!c.attachment;
    const browserDownload = !!c.browserDownload;

    if (!userIntent) {
        if (isApiRpcRequest(u, filename, mime)) return false;
        if (isSignedMediaPlaybackUrl(u)) return false;
        if (!attachment && !browserDownload && PAGE_MIMES.has(mime)) return false;
    }

    const explicit = userIntent || attachment || browserDownload || hasQueryDownloadSignal(u);
    const monitored = (ext) => settings.monitoredExtensions.has(ext);

    const ext = extensionOf(filename) || extensionOf(urlFileName(u)) || MIME_TO_EXT[mime] || "";
    if (ext) {
        if (MEDIA_EXTS.has(ext) && !explicit) return false;
        return monitored(ext);
    }
    if (mime.startsWith("video/")) return explicit && VIDEO_EXTS.some(monitored);
    if (mime.startsWith("audio/")) return explicit && AUDIO_EXTS.some(monitored);

    // Extensionless and of unknown type: only an unambiguous download signal
    // justifies taking it.
    if (hasQueryDownloadSignal(u)) return true;
    if ((attachment || browserDownload) && hasPathDownloadSignal(u)) return true;
    return userIntent;
}

// Firefox sees the response before the browser picks "render" or "save"; this
// reproduces that choice for a top-level or frame navigation.
export function isBrowserDownloadResponse(mime, attachment) {
    return attachment || !isBrowserRenderable(mimeEssence(mime));
}
