// Stellar Download Manager
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

#pragma once

#include <QString>
#include <QStringList>
#include <QList>
#include <QUrl>
#include <QVariant>
#include <QNetworkCookie>

// Reads browser cookies from on-disk profile databases for a given URL.
//
// Supported browsers:
//   Firefox / Flatpak Firefox  — cookies.sqlite (unencrypted)
//   Chrome / Chromium          — Cookies SQLite, AES-256-GCM with DPAPI-wrapped key (Win)
//                                or libsecret/kwallet-wrapped key (Linux)
//   Edge                       — same format as Chrome
//   Brave                      — same format as Chrome
//   Opera / Vivaldi            — same format as Chrome
//
// All reads are done on the calling thread against a COPY of the DB file
// (browsers hold a SQLite exclusive lock while running). The copy is placed
// in a temp file and removed immediately after the query.
//
// Cookie decryption:
//   Windows — AES-256-GCM key stored encrypted with DPAPI in Local State JSON.
//             CryptUnprotectData() used to unwrap it; no admin rights needed.
//   Linux   — key stored in libsecret (Gnome Keyring) or KWallet under the
//             entry "Chrome Safe Storage" / "Chromium Safe Storage" etc.
//             Falls back to empty passphrase (older profile format) on failure.
//
// Thread safety: all methods are re-entrant but NOT thread-safe on the same
// instance. Construct per-call or guard with a mutex.

class BrowserCookieReader
{
public:
    BrowserCookieReader() = default;

    // Returns a semicolon-delimited "name=value;name2=value2" cookie string
    // for all matching cookies from all detected browsers. Suitable for direct
    // use as a Cookie HTTP header or DownloadItem::setCookies().
    // Empty string if no matching cookies found or all reads fail.
    static QString cookiesForUrl(const QUrl &url);

private:
    // Per-browser helpers — each returns a list of matching cookies.
    static QList<QNetworkCookie> readFirefoxCookies(const QUrl &url);
    static QList<QNetworkCookie> readChromiumCookies(const QUrl &url);

    // Returns all Firefox profile directories to check, including Flatpak path.
    static QStringList firefoxProfileDirs();

    // Returns all Chromium-family profile dirs to check (Chrome, Edge, Brave, etc).
    // Each entry is a pair <profileDir, browserName> for key lookup.
    struct ChromiumProfile { QString path; QString appName; };
    static QList<ChromiumProfile> chromiumProfileDirs();

    // Query a SQLite DB (by path) with the given SQL, return rows as lists of QVariants.
    // Opens with immutable=1 URI flag — bypasses SQLite locking, safe while browser runs.
    // Uses Qt SQL with the QSQLITE driver.
    static QList<QList<QVariant>> querySqlite(const QString &dbPath, const QString &sql,
                                              const QVariantList &bindings = {});

    // Decrypt a Chrome/Chromium cookie value.
    // On Windows: DPAPI-unwraps the AES key from localStatePath, then AES-GCM decrypts.
    // On Linux: fetches passphrase from libsecret/kwallet, PBKDF2-derives key, AES-CBC decrypts.
    static QByteArray decryptChromiumValue(const QByteArray &encrypted,
                                           const QString &localStatePath,
                                           const QString &appName);

#ifdef Q_OS_WIN
    // Reads and DPAPI-unwraps the AES-256 key from Chrome's Local State JSON.
    static QByteArray readChromiumAesKey(const QString &localStatePath);
#endif

#ifdef Q_OS_LINUX
    // Retrieves the plaintext passphrase from libsecret (Gnome Keyring).
    // Returns empty QByteArray if unavailable.
    static QByteArray chromiumPassphraseFromSecretService(const QString &appName);
#endif

    // Derive an AES key from a plaintext passphrase (Linux PBKDF2 path).
    static QByteArray pbkdf2DeriveKey(const QByteArray &passphrase);

    // Match a cookie's host/domain against a URL host (handles leading-dot domains).
    static bool cookieDomainMatches(const QString &cookieDomain, const QString &urlHost);

    // Build semicolon string from cookie list, deduplicating by name.
    static QString cookiesToString(const QList<QNetworkCookie> &cookies);
};
