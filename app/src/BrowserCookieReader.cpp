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

#include "BrowserCookieReader.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QMessageAuthenticationCode>
#include <QNetworkCookie>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QUrl>
#include <QVariant>
#include <QCryptographicHash>
#include <atomic>

#ifdef Q_OS_WIN
#  include <windows.h>
#  include <wincrypt.h>
#  pragma comment(lib, "crypt32.lib")
#endif

#ifdef Q_OS_LINUX
#  include <QProcess>
#  include <dlfcn.h>
#endif

#include <QDebug>

// ── AES-256-GCM / AES-128-CBC via Qt's OpenSSL backend ──────────────────────
// Qt 6 exposes QCA or we can call OpenSSL directly via QSslConfiguration.
// Simplest portable path: use Qt's private EVP wrappers through QByteArray +
// openssl headers when present. Instead we'll shell out to the platform crypto:
//   Windows: BCryptDecrypt (AES-GCM)
//   Linux:   openssl EVP via dlopen (avoids hard dep)
//
// Fallback if neither available: return raw bytes (will be garbled but won't crash).

#ifdef Q_OS_WIN
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt.lib")
#endif

// ─────────────────────────────────────────────────────────────────────────────

static QString uniqueConnName()
{
    static std::atomic<int> s_counter{0};
    return QStringLiteral("stellar_bcr_%1_%2")
        .arg(QCoreApplication::applicationPid())
        .arg(s_counter.fetch_add(1));
}

QList<QList<QVariant>> BrowserCookieReader::querySqlite(const QString &dbPath,
                                                        const QString &sql,
                                                        const QVariantList &bindings)
{
    QList<QList<QVariant>> rows;
    if (!QFile::exists(dbPath))
        return rows;

    // Open an in-memory database, then ATTACH the browser's DB file using the
    // file URI with mode=ro. Unlike immutable=1, mode=ro still reads the WAL,
    // so recently written cookies (session cookies, fresh logins) are visible.
    // No temp files, no disk writes.
    const QString connName = uniqueConnName();
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connName);
        db.setDatabaseName(QStringLiteral(":memory:"));
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_URI"));
        if (!db.open()) {
            qDebug() << "[BCR] in-memory open failed:" << db.lastError().text();
        } else {
            // ATTACH as read-only; forward slashes required in URI on all platforms.
            QString fwdPath = dbPath;
            fwdPath.replace(QLatin1Char('\\'), QLatin1Char('/'));
            QSqlQuery attach(db);
            attach.prepare(QStringLiteral("ATTACH DATABASE 'file:%1?mode=ro' AS bdb").arg(fwdPath));
            if (!attach.exec()) {
                qDebug() << "[BCR] ATTACH failed:" << attach.lastError().text() << dbPath;
            } else {
                // Rewrite the caller's SQL to prefix all table refs with "bdb."
                // We do this by running the query directly on the attached schema.
                QSqlQuery q(db);
                // Replace bare table name with bdb-qualified version via the sql as-is;
                // callers already write plain table names — prefix them.
                QString rewritten = sql;
                rewritten.replace(QStringLiteral(" FROM "),  QStringLiteral(" FROM bdb."),  Qt::CaseInsensitive);
                rewritten.replace(QStringLiteral(" JOIN "),  QStringLiteral(" JOIN bdb."),   Qt::CaseInsensitive);
                q.prepare(rewritten);
                for (int i = 0; i < bindings.size(); ++i)
                    q.addBindValue(bindings[i]);
                if (q.exec()) {
                    const int cols = q.record().count();
                    while (q.next()) {
                        QList<QVariant> row;
                        row.reserve(cols);
                        for (int c = 0; c < cols; ++c)
                            row << q.value(c);
                        rows << row;
                    }
                } else {
                    qDebug() << "[BCR] Query failed:" << q.lastError().text();
                }
                QSqlQuery(QStringLiteral("DETACH DATABASE bdb"), db);
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connName);
    return rows;
}

bool BrowserCookieReader::cookieDomainMatches(const QString &cookieDomain,
                                              const QString &urlHost)
{
    // RFC 6265: leading dot means domain + all subdomains.
    QString domain = cookieDomain;
    if (domain.startsWith(QLatin1Char('.')))
        domain = domain.mid(1);
    return urlHost == domain || urlHost.endsWith(QLatin1Char('.') + domain);
}

QString BrowserCookieReader::cookiesToString(const QList<QNetworkCookie> &cookies)
{
    // Deduplicate by name — last writer wins (matches browser behaviour where
    // more-specific domain/path cookies shadow broader ones).
    QMap<QString, QString> seen;
    for (const QNetworkCookie &c : cookies)
        seen[QString::fromUtf8(c.name())] = QString::fromUtf8(c.value());

    QStringList parts;
    parts.reserve(seen.size());
    for (auto it = seen.constBegin(); it != seen.constEnd(); ++it)
        parts << it.key() + QLatin1Char('=') + it.value();
    return parts.join(QLatin1Char(';'));
}

// ── Firefox ──────────────────────────────────────────────────────────────────

QStringList BrowserCookieReader::firefoxProfileDirs()
{
    QStringList dirs;

#ifdef Q_OS_WIN
    QString appData = QDir::homePath() + QStringLiteral("/AppData/Roaming");
    QString profilesIni = appData + QStringLiteral("/Mozilla/Firefox/profiles.ini");
    QStringList bases = { appData + QStringLiteral("/Mozilla/Firefox/Profiles") };
#else
    QString home = QDir::homePath();
    QString profilesIni = home + QStringLiteral("/.mozilla/firefox/profiles.ini");
    QStringList bases = {
        home + QStringLiteral("/.mozilla/firefox"),
        // Flatpak Firefox profile location
        home + QStringLiteral("/.var/app/org.mozilla.firefox/.mozilla/firefox"),
        // Snap Firefox
        home + QStringLiteral("/snap/firefox/common/.mozilla/firefox"),
    };
#endif

    // Parse profiles.ini to enumerate actual profile paths.
    // profiles.ini sections look like:
    //   [Profile0]
    //   Path=Profiles/abc123.default-release
    //   IsRelative=1
    auto parseProfilesIni = [&](const QString &iniPath, const QString &iniBase) {
        QFile f(iniPath);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            return;
        QString currentPath;
        bool isRelative = true;
        while (!f.atEnd()) {
            QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (line.startsWith(QLatin1Char('['))) {
                if (!currentPath.isEmpty()) {
                    QString resolved = isRelative
                        ? iniBase + QLatin1Char('/') + currentPath
                        : currentPath;
                    if (QDir(resolved).exists())
                        dirs << resolved;
                }
                currentPath.clear();
                isRelative = true;
            } else if (line.startsWith(QStringLiteral("Path="))) {
                currentPath = line.mid(5);
            } else if (line.startsWith(QStringLiteral("IsRelative="))) {
                isRelative = (line.mid(11).trimmed() != QLatin1String("0"));
            }
        }
        // Flush last section
        if (!currentPath.isEmpty()) {
            QString resolved = isRelative
                ? iniBase + QLatin1Char('/') + currentPath
                : currentPath;
            if (QDir(resolved).exists())
                dirs << resolved;
        }
    };

#ifdef Q_OS_WIN
    parseProfilesIni(profilesIni, appData + QStringLiteral("/Mozilla/Firefox"));
    // Also enumerate Profiles/ directory directly as fallback
    for (const QString &base : bases) {
        QDir d(base);
        for (const QString &entry : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
            dirs << base + QLatin1Char('/') + entry;
    }
#else
    for (const QString &base : bases) {
        QString ini = base + QStringLiteral("/profiles.ini");
        parseProfilesIni(ini, base);
        // Also enumerate directly
        QDir d(base);
        for (const QString &entry : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
            dirs << base + QLatin1Char('/') + entry;
    }
    Q_UNUSED(profilesIni)
#endif

    // Deduplicate
    dirs.removeDuplicates();
    return dirs;
}

QList<QNetworkCookie> BrowserCookieReader::readFirefoxCookies(const QUrl &url)
{
    QList<QNetworkCookie> result;
    const QString host = url.host();

    for (const QString &profileDir : firefoxProfileDirs()) {
        const QString dbPath = profileDir + QStringLiteral("/cookies.sqlite");
        if (!QFile::exists(dbPath))
            continue;

        // Firefox cookies.sqlite schema:
        // moz_cookies(id, baseDomain, originAttributes, name, value, host, path,
        //             expiry, lastAccessed, creationTime, isSecure, isHttpOnly,
        //             appId, inBrowserElement, sameSite, rawSameSite, schemeMap,
        //             isPartitionedAttributeSet)
        // 'host' field has leading dot for domain cookies; 'value' is plaintext.
        const auto rows = querySqlite(dbPath,
            QStringLiteral("SELECT name, value, host, path, isSecure, isHttpOnly, expiry "
                           "FROM moz_cookies WHERE host = ? OR host = ?"),
            { host, QLatin1Char('.') + host });

        for (const auto &row : rows) {
            if (row.size() < 7) continue;
            const QString cookieHost = row[2].toString();
            if (!cookieDomainMatches(cookieHost, host))
                continue;
            QNetworkCookie c;
            c.setName(row[0].toString().toUtf8());
            c.setValue(row[1].toString().toUtf8());
            c.setDomain(cookieHost);
            c.setPath(row[3].toString());
            c.setSecure(row[4].toBool());
            c.setHttpOnly(row[5].toBool());
            // expiry is Unix timestamp; 0 = session cookie
            if (row[6].toLongLong() > 0)
                c.setExpirationDate(QDateTime::fromSecsSinceEpoch(row[6].toLongLong()));
            result << c;
        }
    }
    return result;
}

// ── Chromium family ──────────────────────────────────────────────────────────

QList<BrowserCookieReader::ChromiumProfile> BrowserCookieReader::chromiumProfileDirs()
{
    QList<ChromiumProfile> result;

#ifdef Q_OS_WIN
    QString local = QDir::homePath() + QStringLiteral("/AppData/Local");
    // Each entry: { base user-data dir, app name for key lookup }
    QList<QPair<QString,QString>> candidates = {
        { local + QStringLiteral("/Google/Chrome/User Data"),           QStringLiteral("Chrome") },
        { local + QStringLiteral("/Google/Chrome Beta/User Data"),      QStringLiteral("Chrome") },
        { local + QStringLiteral("/Google/Chrome SxS/User Data"),       QStringLiteral("Chrome") },
        { local + QStringLiteral("/Chromium/User Data"),                QStringLiteral("Chromium") },
        { local + QStringLiteral("/Microsoft/Edge/User Data"),          QStringLiteral("Edge") },
        { local + QStringLiteral("/BraveSoftware/Brave-Browser/User Data"), QStringLiteral("Brave") },
        { local + QStringLiteral("/Opera Software/Opera Stable"),       QStringLiteral("Opera") },
        { local + QStringLiteral("/Vivaldi/User Data"),                 QStringLiteral("Vivaldi") },
    };
#else
    QString home = QDir::homePath();
    QList<QPair<QString,QString>> candidates = {
        { home + QStringLiteral("/.config/google-chrome"),             QStringLiteral("Chrome") },
        { home + QStringLiteral("/.config/google-chrome-beta"),        QStringLiteral("Chrome") },
        { home + QStringLiteral("/.config/chromium"),                  QStringLiteral("Chromium") },
        { home + QStringLiteral("/.config/microsoft-edge"),            QStringLiteral("Edge") },
        { home + QStringLiteral("/.config/BraveSoftware/Brave-Browser"),QStringLiteral("Brave") },
        { home + QStringLiteral("/.config/opera"),                     QStringLiteral("Opera") },
        { home + QStringLiteral("/.config/vivaldi"),                   QStringLiteral("Vivaldi") },
        // Flatpak Chrome
        { home + QStringLiteral("/.var/app/com.google.Chrome/config/google-chrome"), QStringLiteral("Chrome") },
        // Snap Chrome
        { home + QStringLiteral("/snap/chromium/current/.config/chromium"), QStringLiteral("Chromium") },
    };
#endif

    for (const auto &[base, appName] : candidates) {
        if (!QDir(base).exists())
            continue;
        // Enumerate profiles: Default, Profile 1, Profile 2, …
        QStringList profileNames = { QStringLiteral("Default") };
        QDir d(base);
        for (const QString &entry : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (entry.startsWith(QStringLiteral("Profile")))
                profileNames << entry;
        }
        for (const QString &pn : profileNames) {
            QString profilePath = base + QLatin1Char('/') + pn;
            QString cookiesPath = profilePath + QStringLiteral("/Network/Cookies");
            if (!QFile::exists(cookiesPath))
                cookiesPath = profilePath + QStringLiteral("/Cookies"); // older layout
            if (QFile::exists(cookiesPath))
                result.push_back({ cookiesPath, appName });
        }
    }
    return result;
}

// ── Chromium decryption ──────────────────────────────────────────────────────
//
// Chrome v80+ (all platforms) encrypts cookie values:
//   Windows: "v10" prefix + AES-256-GCM (12-byte nonce, 16-byte tag)
//            AES key wrapped with DPAPI stored in Local State JSON.
//   Linux:   "v10" or "v11" prefix + AES-128-CBC
//            passphrase from libsecret → PBKDF2-HMAC-SHA1 → key
//   Older/unencrypted: raw plaintext (no "v10"/"v11" prefix)

// PBKDF2 key derivation matching Chrome's Linux implementation:
//   iterations=1, keylen=16, salt="saltysalt"
QByteArray BrowserCookieReader::pbkdf2DeriveKey(const QByteArray &passphrase)
{
    // Chrome Linux uses PBKDF2-HMAC-SHA1, 1 iteration, 16 bytes, salt "saltysalt"
    const QByteArray salt = QByteArrayLiteral("saltysalt");
    const int iterations = 1;
    const int keyLen = 16;

    // Qt 6.7+ has QPasswordDigestor::deriveKeyPbkdf2; for broader compat use manual HMAC.
    // F(P, S, c, i) = U1 XOR U2 XOR … XOR Uc where U1 = HMAC(P, S || INT(i))
    QByteArray result;
    int blocksNeeded = (keyLen + 19) / 20; // SHA1 = 20 bytes
    for (int block = 1; block <= blocksNeeded && result.size() < keyLen; ++block) {
        QByteArray seed = salt;
        seed.append(char((block >> 24) & 0xff));
        seed.append(char((block >> 16) & 0xff));
        seed.append(char((block >>  8) & 0xff));
        seed.append(char( block        & 0xff));

        QByteArray u = QMessageAuthenticationCode::hash(seed, passphrase, QCryptographicHash::Sha1);
        QByteArray f = u;
        for (int i = 1; i < iterations; ++i) {
            u = QMessageAuthenticationCode::hash(u, passphrase, QCryptographicHash::Sha1);
            for (int j = 0; j < f.size(); ++j)
                f[j] ^= u[j];
        }
        result.append(f);
    }
    return result.left(keyLen);
}

#ifdef Q_OS_WIN
QByteArray BrowserCookieReader::readChromiumAesKey(const QString &localStatePath)
{
    QFile f(localStatePath);
    if (!f.open(QIODevice::ReadOnly))
        return {};

    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();

    // Path: os_crypt.encrypted_key (base64-encoded, DPAPI-encrypted, prefixed with "DPAPI")
    QByteArray encKeyB64 = doc["os_crypt"]["encrypted_key"].toString().toUtf8();
    if (encKeyB64.isEmpty())
        return {};

    QByteArray encKey = QByteArray::fromBase64(encKeyB64);
    // Strip "DPAPI" prefix (5 bytes)
    if (encKey.startsWith(QByteArrayLiteral("DPAPI")))
        encKey = encKey.mid(5);

    DATA_BLOB input, output;
    input.pbData = reinterpret_cast<BYTE *>(encKey.data());
    input.cbData = static_cast<DWORD>(encKey.size());
    output.pbData = nullptr;
    output.cbData = 0;

    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, 0, &output))
        return {};

    QByteArray key(reinterpret_cast<char *>(output.pbData), static_cast<int>(output.cbData));
    LocalFree(output.pbData);
    return key;
}
#endif // Q_OS_WIN

#ifdef Q_OS_LINUX
QByteArray BrowserCookieReader::chromiumPassphraseFromSecretService(const QString &appName)
{
    // Use secret-tool (part of libsecret-tools) to fetch the passphrase.
    // This avoids a hard link dependency on libsecret.
    // secret-tool lookup application <appName> type password
    QStringList lookupKeys;
    // Chrome stores it under application="chrome" or "chromium" etc (lowercase).
    lookupKeys << QStringLiteral("application") << appName.toLower();
    // Also try the "Chrome Safe Storage" / "Chromium Safe Storage" label lookup
    // that some distros use.
    QStringList labelArg = { QStringLiteral("label"),
                             appName + QStringLiteral(" Safe Storage") };

    auto tryLookup = [](const QStringList &args) -> QByteArray {
        QProcess proc;
        proc.start(QStringLiteral("secret-tool"), QStringList() << QStringLiteral("lookup") << args);
        if (!proc.waitForFinished(3000))
            return {};
        QByteArray out = proc.readAllStandardOutput().trimmed();
        return out;
    };

    QByteArray passphrase = tryLookup(lookupKeys);
    if (passphrase.isEmpty())
        passphrase = tryLookup(labelArg);

    // KWallet fallback via kwallet-query (KDE)
    if (passphrase.isEmpty()) {
        QProcess kwallet;
        kwallet.start(QStringLiteral("kwallet-query"),
                      { QStringLiteral("-r"),
                        appName + QStringLiteral(" Keys"),
                        QStringLiteral("-f"),
                        appName + QStringLiteral(" Safe Storage"),
                        QStringLiteral("kdewallet") });
        if (kwallet.waitForFinished(3000))
            passphrase = kwallet.readAllStandardOutput().trimmed();
    }

    return passphrase;
}
#endif // Q_OS_LINUX

QByteArray BrowserCookieReader::decryptChromiumValue(const QByteArray &encrypted,
                                                     const QString &localStatePath,
                                                     const QString &appName)
{
    if (encrypted.isEmpty())
        return {};

    // Unencrypted (old Chrome / Chromium older than v80): no prefix
    if (!encrypted.startsWith(QByteArrayLiteral("v10")) &&
        !encrypted.startsWith(QByteArrayLiteral("v11"))) {
        return encrypted;
    }

#ifdef Q_OS_WIN
    // Windows: AES-256-GCM
    // Format after "v10" prefix: 12-byte nonce + ciphertext + 16-byte tag
    Q_UNUSED(appName)
    QByteArray aesKey = readChromiumAesKey(localStatePath);
    if (aesKey.isEmpty())
        return {};

    QByteArray payload = encrypted.mid(3); // strip "v10"
    if (payload.size() < 12 + 16)
        return {};

    QByteArray nonce = payload.left(12);
    QByteArray ciphertextWithTag = payload.mid(12);

    // Decrypt AES-256-GCM using BCrypt
    BCRYPT_ALG_HANDLE hAlg = nullptr;
    BCRYPT_KEY_HANDLE hKey = nullptr;
    NTSTATUS status;

    status = BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, nullptr, 0);
    if (!BCRYPT_SUCCESS(status)) return {};

    status = BCryptSetProperty(hAlg,
                               BCRYPT_CHAINING_MODE,
                               reinterpret_cast<PUCHAR>(const_cast<wchar_t *>(BCRYPT_CHAIN_MODE_GCM)),
                               sizeof(BCRYPT_CHAIN_MODE_GCM),
                               0);
    if (!BCRYPT_SUCCESS(status)) { BCryptCloseAlgorithmProvider(hAlg, 0); return {}; }

    status = BCryptGenerateSymmetricKey(hAlg, &hKey,
                                        nullptr, 0,
                                        reinterpret_cast<PUCHAR>(aesKey.data()),
                                        static_cast<ULONG>(aesKey.size()),
                                        0);
    if (!BCRYPT_SUCCESS(status)) { BCryptCloseAlgorithmProvider(hAlg, 0); return {}; }

    // Split ciphertext and tag (last 16 bytes)
    int ciphertextLen = ciphertextWithTag.size() - 16;
    QByteArray ciphertext = ciphertextWithTag.left(ciphertextLen);
    QByteArray tag = ciphertextWithTag.right(16);

    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo;
    BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
    authInfo.pbNonce    = reinterpret_cast<PUCHAR>(nonce.data());
    authInfo.cbNonce    = static_cast<ULONG>(nonce.size());
    authInfo.pbTag      = reinterpret_cast<PUCHAR>(tag.data());
    authInfo.cbTag      = static_cast<ULONG>(tag.size());
    authInfo.pbAuthData = nullptr;
    authInfo.cbAuthData = 0;

    ULONG plainLen = 0;
    status = BCryptDecrypt(hKey,
                           reinterpret_cast<PUCHAR>(ciphertext.data()),
                           static_cast<ULONG>(ciphertext.size()),
                           &authInfo,
                           nullptr, 0,
                           nullptr, 0,
                           &plainLen, 0);
    if (!BCRYPT_SUCCESS(status)) {
        BCryptDestroyKey(hKey);
        BCryptCloseAlgorithmProvider(hAlg, 0);
        return {};
    }

    QByteArray plaintext(static_cast<int>(plainLen), 0);
    status = BCryptDecrypt(hKey,
                           reinterpret_cast<PUCHAR>(ciphertext.data()),
                           static_cast<ULONG>(ciphertext.size()),
                           &authInfo,
                           nullptr, 0,
                           reinterpret_cast<PUCHAR>(plaintext.data()),
                           plainLen,
                           &plainLen, 0);
    BCryptDestroyKey(hKey);
    BCryptCloseAlgorithmProvider(hAlg, 0);

    if (!BCRYPT_SUCCESS(status))
        return {};

    return plaintext.left(static_cast<int>(plainLen));

#elif defined(Q_OS_LINUX)
    // Linux: AES-128-CBC, PKCS7 padding
    // Key derived from passphrase via PBKDF2-HMAC-SHA1, IV = 16 zero bytes
    Q_UNUSED(localStatePath)
    QByteArray passphrase = chromiumPassphraseFromSecretService(appName);
    if (passphrase.isEmpty())
        passphrase = QByteArrayLiteral("peanuts"); // Chrome default when no keyring

    QByteArray key = pbkdf2DeriveKey(passphrase);
    QByteArray payload = encrypted.mid(3); // strip "v10" or "v11"

    // Decrypt via OpenSSL through dlopen to avoid hard dependency
    // Try loading libcrypto dynamically
    using EVP_CIPHER_CTX_ptr = void *;
    using fn_EVP_CIPHER_CTX_new     = EVP_CIPHER_CTX_ptr (*)();
    using fn_EVP_CIPHER_CTX_free    = void (*)(EVP_CIPHER_CTX_ptr);
    using fn_EVP_DecryptInit_ex     = int (*)(EVP_CIPHER_CTX_ptr, const void *, void *, const unsigned char *, const unsigned char *);
    using fn_EVP_DecryptUpdate      = int (*)(EVP_CIPHER_CTX_ptr, unsigned char *, int *, const unsigned char *, int);
    using fn_EVP_DecryptFinal_ex    = int (*)(EVP_CIPHER_CTX_ptr, unsigned char *, int *);
    using fn_EVP_aes_128_cbc        = const void * (*)();

    static void *s_libcrypto = nullptr;
    static fn_EVP_CIPHER_CTX_new     s_ctx_new  = nullptr;
    static fn_EVP_CIPHER_CTX_free    s_ctx_free = nullptr;
    static fn_EVP_DecryptInit_ex     s_init     = nullptr;
    static fn_EVP_DecryptUpdate      s_update   = nullptr;
    static fn_EVP_DecryptFinal_ex    s_final    = nullptr;
    static fn_EVP_aes_128_cbc        s_aes128   = nullptr;

    if (!s_libcrypto) {
        // Try common libcrypto SO names
        const char *libs[] = { "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.so", nullptr };
        for (int i = 0; libs[i]; ++i) {
            s_libcrypto = dlopen(libs[i], RTLD_LAZY | RTLD_LOCAL);
            if (s_libcrypto) break;
        }
        if (s_libcrypto) {
            s_ctx_new  = reinterpret_cast<fn_EVP_CIPHER_CTX_new>(dlsym(s_libcrypto,  "EVP_CIPHER_CTX_new"));
            s_ctx_free = reinterpret_cast<fn_EVP_CIPHER_CTX_free>(dlsym(s_libcrypto, "EVP_CIPHER_CTX_free"));
            s_init     = reinterpret_cast<fn_EVP_DecryptInit_ex>(dlsym(s_libcrypto,  "EVP_DecryptInit_ex"));
            s_update   = reinterpret_cast<fn_EVP_DecryptUpdate>(dlsym(s_libcrypto,   "EVP_DecryptUpdate"));
            s_final    = reinterpret_cast<fn_EVP_DecryptFinal_ex>(dlsym(s_libcrypto, "EVP_DecryptFinal_ex"));
            s_aes128   = reinterpret_cast<fn_EVP_aes_128_cbc>(dlsym(s_libcrypto,     "EVP_aes_128_cbc"));
        }
    }

    if (!s_libcrypto || !s_ctx_new || !s_init || !s_update || !s_final || !s_aes128) {
        qDebug() << "[BCR] libcrypto unavailable, cannot decrypt Chromium cookies on Linux";
        return {};
    }

    // IV is 16 space characters (Chrome's fixed IV)
    QByteArray iv(16, ' ');

    EVP_CIPHER_CTX_ptr ctx = s_ctx_new();
    if (!ctx) return {};

    const void *cipher = s_aes128();
    s_init(ctx, cipher, nullptr,
           reinterpret_cast<const unsigned char *>(key.constData()),
           reinterpret_cast<const unsigned char *>(iv.constData()));

    QByteArray plaintext(payload.size() + 16, 0);
    int outLen1 = 0, outLen2 = 0;
    s_update(ctx,
             reinterpret_cast<unsigned char *>(plaintext.data()), &outLen1,
             reinterpret_cast<const unsigned char *>(payload.constData()), payload.size());
    s_final(ctx,
            reinterpret_cast<unsigned char *>(plaintext.data()) + outLen1, &outLen2);
    s_ctx_free(ctx);

    return plaintext.left(outLen1 + outLen2);

#else
    Q_UNUSED(localStatePath)
    Q_UNUSED(appName)
    // macOS not targeted; return raw bytes so at least something is returned.
    return encrypted.mid(3);
#endif
}

QList<QNetworkCookie> BrowserCookieReader::readChromiumCookies(const QUrl &url)
{
    QList<QNetworkCookie> result;
    const QString host = url.host();

    for (const ChromiumProfile &profile : chromiumProfileDirs()) {

        // Determine Local State path (one level up from the profile path,
        // which itself is <UserData>/<ProfileName>/Network/Cookies or
        // <UserData>/<ProfileName>/Cookies).
        // Walk up to find the directory containing "Local State".
        QString localStatePath;
        {
            QFileInfo fi(profile.path);
            QDir d = fi.dir(); // profile dir or Network dir
            // Go up until we find "Local State" or exhaust parents
            for (int depth = 0; depth < 4; ++depth) {
                QString candidate = d.filePath(QStringLiteral("Local State"));
                if (QFile::exists(candidate)) {
                    localStatePath = candidate;
                    break;
                }
                if (!d.cdUp()) break;
            }
        }

        // Chrome Cookies schema (v20+):
        // cookies(creation_utc, host_key, top_frame_site_key, name, value,
        //         encrypted_value, path, expires_utc, is_secure, is_httponly,
        //         last_access_utc, has_expires, is_persistent, priority,
        //         samesite, source_scheme, source_port, is_same_party,
        //         last_update_utc)
        const auto rows = querySqlite(profile.path,
            QStringLiteral("SELECT name, value, encrypted_value, host_key, path, "
                           "is_secure, is_httponly, expires_utc "
                           "FROM cookies WHERE host_key = ? OR host_key = ?"),
            { host, QLatin1Char('.') + host });

        for (const auto &row : rows) {
            if (row.size() < 8) continue;
            const QString cookieHost = row[3].toString();
            if (!cookieDomainMatches(cookieHost, host))
                continue;

            QString value = row[1].toString();
            if (value.isEmpty()) {
                // Encrypted value
                QByteArray enc = row[2].toByteArray();
                if (!enc.isEmpty()) {
                    QByteArray plain = decryptChromiumValue(enc, localStatePath, profile.appName);
                    value = QString::fromUtf8(plain);
                }
            }
            if (value.isEmpty())
                continue;

            QNetworkCookie c;
            c.setName(row[0].toString().toUtf8());
            c.setValue(value.toUtf8());
            c.setDomain(cookieHost);
            c.setPath(row[4].toString());
            c.setSecure(row[5].toBool());
            c.setHttpOnly(row[6].toBool());
            // Chrome stores time as microseconds since 1601-01-01 (Windows FILETIME epoch).
            // Convert to Unix: subtract 11644473600 seconds, then divide by 1e6.
            qint64 chromiumTime = row[7].toLongLong();
            if (chromiumTime > 0) {
                qint64 unixMs = (chromiumTime / 1000) - Q_INT64_C(11644473600000);
                if (unixMs > 0)
                    c.setExpirationDate(QDateTime::fromMSecsSinceEpoch(unixMs));
            }
            result << c;
        }
    }
    return result;
}

// ── Public API ───────────────────────────────────────────────────────────────

QString BrowserCookieReader::cookiesForUrl(const QUrl &url)
{
    if (!url.isValid() || url.host().isEmpty())
        return {};

    QList<QNetworkCookie> all;
    all << readFirefoxCookies(url);
    all << readChromiumCookies(url);

    if (all.isEmpty())
        return {};

    // Filter expired cookies
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QList<QNetworkCookie> valid;
    valid.reserve(all.size());
    for (const QNetworkCookie &c : all) {
        if (!c.expirationDate().isValid() || c.expirationDate() > now)
            valid << c;
    }

    return cookiesToString(valid);
}
