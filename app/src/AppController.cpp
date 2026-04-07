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

#include "AppController.h"
#include "DownloadItem.h"
#include "AppVersion.h"
#include <QLocalServer>
#include <QLocalSocket>
#include <QUuid>
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDesktopServices>
#if defined(STELLAR_WINDOWS)
#  include <windows.h>
#endif
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QFileInfo>
#include <QGuiApplication>
#include <QClipboard>
#include <QProcess>

AppController::AppController(QObject *parent) : QObject(parent) {
    m_nam           = new QNetworkAccessManager(this);
    m_settings      = new AppSettings(this);
    m_queue         = new DownloadQueue(this);
    m_downloadModel = new DownloadTableModel(this);
    m_categoryModel = new CategoryModel(this);
    m_nativeHost    = new NativeMessagingHost(this);
    m_tray          = new SystemTrayIcon(this);
    m_db            = new DownloadDatabase(this);
    m_queueDb       = new QueueDatabase(this);
    m_queueModel    = new QueueModel(this);

    // Load queues from disk
    if (m_queueDb->open()) {
        const auto queues = m_queueDb->loadAll(this);
        for (Queue *q : queues) {
            m_queueModel->addQueue(q);
        }
    }

    // Ensure we have the default queues (in order)
    if (m_queueModel->queueById("main-download") == nullptr) {
        Queue *mainQueue = new Queue("main-download", this);
        mainQueue->setName("Main download queue");
        mainQueue->setIsDownloadQueue(true);
        m_queueModel->addQueue(mainQueue);
        m_queueDb->save(mainQueue);
    }

    if (m_queueModel->queueById("main-sync") == nullptr) {
        Queue *syncQueue = new Queue("main-sync", this);
        syncQueue->setName("Synchronization queue");
        syncQueue->setIsDownloadQueue(false);  // Synchronization queue
        m_queueModel->addQueue(syncQueue);
        m_queueDb->save(syncQueue);
    }

    // Download limits queue at the bottom
    if (m_queueModel->queueById("download-limits") == nullptr) {
        Queue *limitsQueue = new Queue("download-limits", this);
        limitsQueue->setName("Download limits");
        limitsQueue->setIsDownloadQueue(true);
        m_queueModel->addQueue(limitsQueue);
        m_queueDb->save(limitsQueue);
    }

    // Debounce DB writes: flush dirty items every 2 seconds
    m_saveTimer = new QTimer(this);
    m_saveTimer->setInterval(2000);
    m_saveTimer->setSingleShot(true);
    connect(m_saveTimer, &QTimer::timeout, this, &AppController::flushDirty);

    // Scheduler timer: check queue schedules every 10 seconds for better timing accuracy
    m_schedulerTimer = new QTimer(this);
    m_schedulerTimer->setInterval(10000);  // 10 seconds
    connect(m_schedulerTimer, &QTimer::timeout, this, &AppController::checkQueueSchedules);
    // Also emit minutesUntilNextQueueChanged on each timer tick to update UI countdown
    connect(m_schedulerTimer, &QTimer::timeout, this, &AppController::minutesUntilNextQueueChanged);
    m_schedulerTimer->start();

    // Wire up queue with nam and settings
    m_queue->setNam(m_nam);
    m_queue->setMaxConcurrent(m_settings->maxConcurrent());
    m_queue->setSegmentsPerDownload(m_settings->segmentsPerDownload());
    m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps());

    connect(m_settings, &AppSettings::maxConcurrentChanged,
            this, [this]() { m_queue->setMaxConcurrent(m_settings->maxConcurrent()); });
    connect(m_settings, &AppSettings::segmentsPerDownloadChanged,
            this, [this]() { m_queue->setSegmentsPerDownload(m_settings->segmentsPerDownload()); });
    connect(m_settings, &AppSettings::globalSpeedLimitKBpsChanged,
            this, [this]() { m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps()); });

    connect(m_queue, &DownloadQueue::itemAdded,          m_downloadModel, &DownloadTableModel::addItem);
    connect(m_queue, &DownloadQueue::itemRemoved,        m_downloadModel, &DownloadTableModel::removeItem);
    connect(m_queue, &DownloadQueue::activeCountChanged, this, &AppController::activeDownloadsChanged);
    connect(m_queue, &DownloadQueue::itemCompleted,      this, [this](DownloadItem *item) {
        emit downloadCompleted(item);
    });

    // Persist new items immediately; skip during initial restore (handled separately)
    connect(m_queue, &DownloadQueue::itemAdded, this, [this](DownloadItem *item) {
        if (!m_restoring) {
            m_db->save(item);
            watchItem(item);
        }
    });
    // Remove from DB when cancelled
    connect(m_queue, &DownloadQueue::itemRemoved, this, [this](const QString &id) {
        m_dirtyIds.remove(id);
        m_db->remove(id);
    });
    // Flush dirty writes immediately on completion or error (status changes)
    connect(m_queue, &DownloadQueue::itemCompleted, this, [this](DownloadItem *item) {
        m_db->save(item);
        m_dirtyIds.remove(item->id());
    });

    connect(m_nativeHost, &NativeMessagingHost::downloadRequested,
            this, [this](const QString &url, const QString &filename,
                         const QString &referrer, const QString &cookies) {
                Q_UNUSED(filename);
                addUrl(url, {}, {}, {}, true, cookies, referrer);
            });

    // Tray connections
    connect(m_tray, &SystemTrayIcon::showRequested,        this, &AppController::showWindowRequested);
    connect(m_tray, &SystemTrayIcon::quitRequested,        &QCoreApplication::quit);
    connect(m_tray, &SystemTrayIcon::addUrlRequested,      this, [this]() { emit showWindowRequested(); });
    connect(m_tray, &SystemTrayIcon::githubRequested,       this, &AppController::trayGithubRequested);
    connect(m_tray, &SystemTrayIcon::aboutRequested,        this, &AppController::trayAboutRequested);
    connect(m_tray, &SystemTrayIcon::speedLimiterRequested, this, &AppController::traySpeedLimiterRequested);
    connect(m_tray, &SystemTrayIcon::contextMenuRequested,  this, &AppController::contextMenuRequested);

    // IPC server — receives download requests forwarded by --native-messaging subprocesses.
    // Register the native messaging host on every startup so the browser
    // extension works without requiring the user to open the setup dialog.
    {
        QString err = registerNativeHost();
        if (err.isEmpty())
            qDebug() << "[NativeHost] registered OK, manifest:" << nativeHostManifestPath();
        else
            qDebug() << "[NativeHost] registration FAILED:" << err;
    }

    m_ipcServer = new QLocalServer(this);
    QLocalServer::removeServer(QStringLiteral("StellarDownloadManager")); // clean up stale socket
    m_ipcServer->listen(QStringLiteral("StellarDownloadManager"));
    connect(m_ipcServer, &QLocalServer::newConnection, this, [this]() {
        QLocalSocket *sock = m_ipcServer->nextPendingConnection();
        connect(sock, &QLocalSocket::readyRead, this, [this, sock]() {
            const QByteArray data = sock->readAll();
            const QJsonObject obj = QJsonDocument::fromJson(data).object();
            const QString type = obj.value(QStringLiteral("type")).toString();
            if (type == QStringLiteral("download")) {
                const QString url       = obj.value(QStringLiteral("url")).toString();
                const QString name      = obj.value(QStringLiteral("filename")).toString();
                const QString cookies   = obj.value(QStringLiteral("cookies")).toString();
                const QString referrer  = obj.value(QStringLiteral("referrer")).toString();
                const QString pageUrl   = obj.value(QStringLiteral("pageUrl")).toString();
                qDebug() << "[IPC] download received, hasCookies=" << !cookies.isEmpty()
                         << "cookieLen=" << cookies.size();
                if (m_settings->startImmediately()) {
                    // Skip the file info dialog — start immediately, bring main window
                    addUrl(url, {}, {}, {}, true, cookies, referrer, pageUrl);
                    emit showWindowRequested();
                } else {
                    // Show the file info dialog — do NOT bring the main window,
                    // the dialog will raise itself via onVisibleChanged.
                    if (!cookies.isEmpty())
                        m_pendingCookies[url] = cookies;
                    if (!referrer.isEmpty())
                        m_pendingReferrers[url] = referrer;
                    if (!pageUrl.isEmpty())
                        m_pendingPageUrls[url] = pageUrl;
                    emit interceptedDownloadRequested(url, name);
                }
                sock->deleteLater();
            } else if (type == QStringLiteral("focus")) {
                emit showWindowRequested();
                sock->deleteLater();
            } else {
                sock->deleteLater();
            }
        });
        connect(sock, &QLocalSocket::disconnected, sock, &QLocalSocket::deleteLater);
    });

    m_tray->show();

    // Flush any pending writes when the app is about to quit
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this]() {
        flushDirty();
    });

    // Load persisted downloads — guard with m_restoring so itemAdded doesn't re-save them
    if (m_db->open()) {
        m_restoring = true;
        const auto items = m_db->loadAll();
        for (DownloadItem *item : items) {
            m_queue->enqueueRestored(item);
            watchItem(item);
        }
        m_restoring = false;
    }

    // Initial scheduler check
    checkQueueSchedules();

    // If "always turn on speed limiter on startup" is set, restore saved limit
    if (m_settings->speedLimiterOnStartup() && m_settings->globalSpeedLimitKBps() == 0
            && m_settings->savedSpeedLimitKBps() > 0) {
        m_settings->setGlobalSpeedLimitKBps(m_settings->savedSpeedLimitKBps());
    }
}

int AppController::activeDownloads() const {
    return m_queue->activeCount();
}

void AppController::setSelectedCategory(const QString &v) {
    if (m_selectedCategory != v) {
        m_selectedCategory = v;
        m_downloadModel->setFilterCategory(v);
        emit selectedCategoryChanged();
    }
}

void AppController::addUrl(const QString &url, const QString &savePath,
                           const QString &category, const QString &description,
                           bool startNow, const QString &cookies,
                           const QString &referrer, const QString &parentUrl,
                           const QString &username, const QString &password) {
    if (url.trimmed().isEmpty()) return;

    const QString id   = generateId();
    const QUrl    qurl = QUrl::fromUserInput(url);
    auto *item = new DownloadItem(id, qurl);

    if (!cookies.isEmpty())
        item->setCookies(cookies);
    if (!referrer.isEmpty())
        item->setReferrer(referrer);
    if (!parentUrl.isEmpty())
        item->setParentUrl(parentUrl);
    if (!username.isEmpty())
        item->setUsername(username);
    if (!password.isEmpty())
        item->setPassword(password);

    const QString resolvedCategory = !category.isEmpty()
        ? category
        : m_categoryModel->categoryForUrl(qurl, item->filename());
    item->setCategory(resolvedCategory);

    if (!description.isEmpty())
        item->setDescription(description);

    if (!savePath.isEmpty()) {
        item->setSavePath(savePath);
    } else if (m_settings->defaultSavePath().isEmpty()) {
        item->setSavePath(m_categoryModel->savePathForCategory(resolvedCategory));
    } else {
        item->setSavePath(m_settings->defaultSavePath());
    }

    if (startNow) {
        m_queue->enqueue(item);
    } else {
        m_queue->enqueueHeld(item);
    }
    emit downloadAdded(item);
}

QObject *AppController::findDuplicateUrl(const QString &url) const {
    const QUrl qurl = QUrl::fromUserInput(url);
    return m_downloadModel->itemByUrl(qurl);
}

QString AppController::generateNumberedFilename(const QString &filename) const {
    const QString base = QFileInfo(filename).completeBaseName();
    const QString ext  = QFileInfo(filename).suffix();
    const QString dotExt = ext.isEmpty() ? QString{} : QStringLiteral(".") + ext;

    int n = 2;
    while (n < 1000) {
        QString candidate = base + QStringLiteral(" (") + QString::number(n) + QStringLiteral(")") + dotExt;
        // Check if any existing item already has this filename
        bool taken = false;
        for (auto *item : m_queue->items()) {
            if (item->filename().compare(candidate, Qt::CaseInsensitive) == 0) {
                taken = true;
                break;
            }
        }
        if (!taken) return candidate;
        ++n;
    }
    return filename; // fallback (should never reach)
}

void AppController::copyToClipboard(const QString &text) const {
    QGuiApplication::clipboard()->setText(text);
}

void AppController::openExtensionFolder() const {
    // Try installed path first (extensions/firefox next to the binary)
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString installedPath = appDir + QStringLiteral("/extensions/firefox");
    if (QFile::exists(installedPath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(installedPath));
        return;
    }
    // Dev build: binary is in build/windows-debug/ — project root is 3 levels up
    const QString devPath = QDir::cleanPath(appDir + QStringLiteral("/../../../extensions/firefox"));
    if (QFile::exists(devPath)) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(devPath));
        return;
    }
    // Final fallback: just open the app directory
    QDesktopServices::openUrl(QUrl::fromLocalFile(appDir));
}

QString AppController::nativeHostManifestPath() const {
#if defined(STELLAR_LINUX)
    // On Linux the app dir may be read-only (e.g. Flatpak /app/bin/).
    // Use a writable user-data directory instead.
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dataDir);
    return dataDir + QStringLiteral("/com.stellar.downloadmanager.json");
#else
    // Windows: store next to the executable (always writable for portable installs).
    return QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.json"));
#endif
}

QString AppController::nativeHostDiagnostics() const {
    QStringList lines;

    const QString manifestPath = nativeHostManifestPath();
    lines << QStringLiteral("Manifest path: ") + manifestPath;

    const bool exists = QFile::exists(manifestPath);
    lines << QStringLiteral("Manifest file exists: ") + (exists ? QStringLiteral("YES") : QStringLiteral("NO"));

    if (exists) {
        QFile f(manifestPath);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            lines << QStringLiteral("Manifest contents:");
            lines << QString::fromUtf8(f.readAll());
        } else {
            lines << QStringLiteral("Could not read manifest: ") + f.errorString();
        }
    }

#if defined(STELLAR_WINDOWS)
    const QString subKey =
        QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager");
    HKEY hKey = nullptr;
    LONG res = RegOpenKeyExW(HKEY_CURRENT_USER,
                             reinterpret_cast<LPCWSTR>(subKey.utf16()),
                             0, KEY_QUERY_VALUE, &hKey);
    if (res != ERROR_SUCCESS) {
        lines << QStringLiteral("Registry key: NOT FOUND (error %1)").arg(res);
    } else {
        WCHAR buf[MAX_PATH] = {};
        DWORD sz = sizeof(buf);
        DWORD type = 0;
        res = RegQueryValueExW(hKey, L"", nullptr, &type,
                               reinterpret_cast<LPBYTE>(buf), &sz);
        RegCloseKey(hKey);
        if (res == ERROR_SUCCESS)
            lines << QStringLiteral("Registry value: ") + QString::fromWCharArray(buf);
        else
            lines << QStringLiteral("Registry default value: NOT SET (error %1)").arg(res);
    }
#endif

    return lines.join(QLatin1Char('\n'));
}

QString AppController::registerNativeHost() const {
    const QString manifestPath = nativeHostManifestPath();

#if defined(STELLAR_LINUX)
    // On Linux the executable path used in the manifest depends on whether
    // we are running inside a Flatpak sandbox.  Inside Flatpak,
    // applicationFilePath() returns "/app/bin/Stellar" which is invisible to
    // the host Firefox process.  We write a tiny wrapper script to a
    // host-writable location that calls "flatpak run ..." so Firefox can
    // execute it directly.

    const bool isFlatpak = qEnvironmentVariableIsSet("FLATPAK_ID");
    const QString flatpakId = QString::fromLocal8Bit(qgetenv("FLATPAK_ID"));
    QString hostExePath;  // path Firefox will put in the manifest

    if (isFlatpak) {
        // Write a wrapper script: ~/.local/share/<AppName>/stellar-nm-wrapper.sh
        const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
        QDir().mkpath(dataDir);
        const QString wrapperPath = dataDir + QStringLiteral("/stellar-nm-wrapper.sh");

        QFile wrapper(wrapperPath);
        if (!wrapper.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            return QStringLiteral("Could not write wrapper script: ") + wrapperPath
                   + QStringLiteral("\nError: ") + wrapper.errorString();
        wrapper.write(QStringLiteral("#!/bin/bash\nexec flatpak run %1 \"$@\"\n")
                      .arg(flatpakId).toUtf8());
        wrapper.close();
        // Make it executable
        wrapper.setPermissions(
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
            QFileDevice::ReadGroup | QFileDevice::ExeGroup |
            QFileDevice::ReadOther | QFileDevice::ExeOther);
        hostExePath = wrapperPath;
    } else {
        hostExePath = QCoreApplication::applicationFilePath();
    }

    QJsonObject manifest;
    manifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    manifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    manifest[QStringLiteral("path")]        = hostExePath;
    manifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    manifest[QStringLiteral("allowed_extensions")] = QJsonArray{ QStringLiteral("stellar@stellar.moe") };

    const QByteArray json = QJsonDocument(manifest).toJson(QJsonDocument::Indented);

    // Write the manifest source file (used for manual cp instructions).
    {
        QDir().mkpath(QFileInfo(manifestPath).absolutePath());
        QFile f(manifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write manifest file: ") + manifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(json);
    }

#else
    // Non-Linux: exe path is always the running binary.
    const QString exePath = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());

    QJsonObject manifest;
    manifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    manifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    manifest[QStringLiteral("path")]        = exePath;
    manifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    manifest[QStringLiteral("allowed_extensions")] = QJsonArray{ QStringLiteral("stellar@stellar.moe") };

    const QByteArray json = QJsonDocument(manifest).toJson(QJsonDocument::Indented);

    // Write the manifest file next to the executable.
    {
        QDir().mkpath(QCoreApplication::applicationDirPath());
        QFile f(manifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write manifest file: ") + manifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(json);
    }
#endif

#if defined(STELLAR_WINDOWS)
    // Use Win32 API directly — QSettings default-value behaviour is unreliable.
    // Firefox reads the default (unnamed) value of this key to find the manifest.
    {
        const QString subKey =
            QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager");
        HKEY hKey = nullptr;
        LONG res = RegCreateKeyExW(
            HKEY_CURRENT_USER,
            reinterpret_cast<LPCWSTR>(subKey.utf16()),
            0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
            &hKey, nullptr);
        if (res != ERROR_SUCCESS || !hKey)
            return QStringLiteral("Failed to create registry key (error %1).\nPlease register manually.").arg(res);

        const std::wstring wval = reinterpret_cast<const wchar_t *>(manifestPath.utf16());
        res = RegSetValueExW(
            hKey, L"", 0, REG_SZ,
            reinterpret_cast<const BYTE *>(wval.c_str()),
            static_cast<DWORD>((wval.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(hKey);

        if (res != ERROR_SUCCESS)
            return QStringLiteral("Failed to write registry value (error %1).\nPlease register manually.").arg(res);
    }
#elif defined(STELLAR_LINUX)
    // Copy manifest to all known Firefox native-messaging-hosts directories.
    // Standard Firefox: ~/.mozilla/native-messaging-hosts/
    // Snap Firefox:     ~/snap/firefox/common/.mozilla/native-messaging-hosts/
    const QStringList mozDirs = {
        QDir::homePath() + QStringLiteral("/.mozilla/native-messaging-hosts"),
        QDir::homePath() + QStringLiteral("/snap/firefox/common/.mozilla/native-messaging-hosts"),
    };

    QString lastError;
    bool anyOk = false;
    for (const QString &mozDir : mozDirs) {
        // Only write to snap path if the snap directory exists (avoids creating
        // snap dirs on systems that don't have snap Firefox).
        if (mozDir.contains(QStringLiteral("/snap/")) &&
            !QDir(QDir::homePath() + QStringLiteral("/snap/firefox")).exists())
            continue;

        if (!QDir().mkpath(mozDir)) {
            lastError = QStringLiteral("Could not create directory: ") + mozDir;
            continue;
        }
        const QString dest = mozDir + QStringLiteral("/com.stellar.downloadmanager.json");
        QFile::remove(dest);
        QFile src(manifestPath);
        if (!src.copy(dest)) {
            lastError = QStringLiteral("Could not copy manifest to: ") + dest
                        + QStringLiteral("\nError: ") + src.errorString();
        } else {
            anyOk = true;
        }
    }

    if (!anyOk)
        return lastError.isEmpty()
               ? QStringLiteral("No Firefox installation directories found.")
               : lastError;
#else
    return QStringLiteral("Automatic registration is not supported on this platform.\nPlease register manually using the instructions below.");
#endif

    return {};  // success
}

void AppController::setPendingCookies(const QString &url, const QString &cookies) {
    if (!cookies.isEmpty())
        m_pendingCookies[url] = cookies;
}

QString AppController::takePendingCookies(const QString &url) {
    return m_pendingCookies.take(url);
}

QString AppController::takePendingReferrer(const QString &url) {
    return m_pendingReferrers.take(url);
}

QString AppController::takePendingPageUrl(const QString &url) {
    return m_pendingPageUrls.take(url);
}

void AppController::deleteAllCompleted(int mode) {
    // Collect IDs of all completed items first, then delete
    QStringList toDelete;
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (item->status() == QStringLiteral("Completed"))
            toDelete << item->id();
    }
    for (const QString &id : toDelete)
        deleteDownload(id, mode);
}

void AppController::pauseAllDownloads() {
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (item->status() == QStringLiteral("Downloading") || item->status() == QStringLiteral("Queued"))
            m_queue->pause(item->id());
    }
}

void AppController::sortDownloads(const QString &column, bool ascending) {
    m_downloadModel->sortBy(column, ascending);
}

void AppController::setDownloadSpeedLimit(const QString &downloadId, int kbps) {
    // Set on the item itself (for persistence and future starts)
    auto *item = m_downloadModel->itemById(downloadId);
    if (item)
        item->setSpeedLimitKBps(kbps);
    // Also set on active worker if it exists
    m_queue->setDownloadSpeedLimit(downloadId, kbps);
}

void AppController::notifyInterceptRejected(const QString &url) {
    if (url.isEmpty() || !m_settings->showExceptionsDialog()) return;
    int &count = m_interceptRejectCounts[url];
    ++count;
    if (count >= 2) {
        m_interceptRejectCounts.remove(url);
        emit exceptionDialogRequested(url);
    }
}

void AppController::addExcludedAddress(const QString &pattern) {
    if (pattern.trimmed().isEmpty()) return;
    QStringList list = m_settings->excludedAddresses();
    if (!list.contains(pattern.trimmed())) {
        list.prepend(pattern.trimmed());
        m_settings->setExcludedAddresses(list);
    }
}

void AppController::pauseDownload(const QString &id) {
    m_queue->pause(id);
}

void AppController::resumeDownload(const QString &id) {
    m_queue->resume(id);
}

void AppController::deleteDownload(const QString &id, int mode) {
    // Capture file path and URL before the item is removed from queue
    QString filePath;
    QString itemUrl;
    {
        auto *item = m_downloadModel->itemById(id);
        if (item) {
            itemUrl = item->url().toString();
            if (mode > 0 && item->status() == QStringLiteral("Completed"))
                filePath = item->savePath() + QStringLiteral("/") + item->filename();
        }
    }

    m_queue->cancel(id);

    // Track cancellations for the exceptions dialog feature
    if (!itemUrl.isEmpty() && m_settings->showExceptionsDialog()) {
        int &count = m_cancelCounts[itemUrl];
        ++count;
        if (count >= 2) {
            m_cancelCounts.remove(itemUrl);
            emit exceptionDialogRequested(itemUrl);
        }
    }

    if (!filePath.isEmpty()) {
        if (mode == 2) {
            QFile::moveToTrash(filePath);
        } else {
            QFile::remove(filePath);
        }
    }
}

void AppController::openFile(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath() + QStringLiteral("/") + item->filename()));
}

void AppController::openFolder(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
}

void AppController::openFolderSelectFile(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

#if defined(STELLAR_WINDOWS)
    const QString filePath = item->savePath() + QDir::separator() + item->filename();
    const QString nativePath = QDir::toNativeSeparators(filePath);

    // Pass the flag and the path as separate elements in the list
    QStringList arguments;
    arguments << "/select," << nativePath;

    QProcess::startDetached(QStringLiteral("explorer.exe"), arguments);

#else
    // On Linux/Mac, open the folder and select the file if possible
    QDesktopServices::openUrl(QUrl::fromLocalFile(item->savePath()));
#endif
}

void AppController::setDownloadUsername(const QString &id, const QString &username) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setUsername(username); scheduleSave(id); }
}

void AppController::setDownloadPassword(const QString &id, const QString &password) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setPassword(password); scheduleSave(id); }
}

bool AppController::moveDownloadFile(const QString &id, const QString &newFilePath) {
    auto *item = m_downloadModel->itemById(id);
    if (!item || item->status() != QStringLiteral("Completed")) return false;

    const QString oldPath = item->savePath() + QStringLiteral("/") + item->filename();
    const QFileInfo newInfo(newFilePath);
    const QString newDir = newInfo.absolutePath();
    const QString newName = newInfo.fileName();

    if (!QFile::rename(oldPath, newFilePath)) return false;

    item->setSavePath(newDir);
    item->setFilename(newName);
    scheduleSave(id);
    return true;
}

void AppController::enableSpeedLimiter() {
    int limit = m_settings->savedSpeedLimitKBps();
    if (limit <= 0) limit = 500;
    m_settings->setGlobalSpeedLimitKBps(limit);
}

void AppController::disableSpeedLimiter() {
    const int current = m_settings->globalSpeedLimitKBps();
    if (current > 0) m_settings->setSavedSpeedLimitKBps(current);
    m_settings->setGlobalSpeedLimitKBps(0);
}

void AppController::copyDownloadFilename(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (item) {
        copyToClipboard(item->filename());
    }
}


QString AppController::appVersion() const { return QStringLiteral(STELLAR_VERSION); }
QString AppController::buildTime()   const { return QStringLiteral(STELLAR_BUILD_TIME); }
QString AppController::qtVersion()   const { return QString::fromLatin1(qVersion()); }

QString AppController::clipboardUrl() const {
    const QString text = QGuiApplication::clipboard()->text().trimmed();
    if (text.startsWith(QLatin1String("http://")) || text.startsWith(QLatin1String("https://"))
        || text.startsWith(QLatin1String("ftp://"))) {
        // Only return the first line in case of multi-line clipboard
        return text.split(QLatin1Char('\n')).first().trimmed();
    }
    return {};
}

void AppController::setDownloadCategory(const QString &downloadId, const QString &categoryId) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item) return;
    item->setCategory(categoryId);
    scheduleSave(downloadId);
}

void AppController::setDownloadQueue(const QString &downloadId, const QString &queueId) {
    auto *item = m_downloadModel->itemById(downloadId);
    if (!item) return;
    item->setQueueId(queueId);
    scheduleSave(downloadId);
}

void AppController::moveUpInQueue(const QString &downloadId) {
    m_queue->moveUp(downloadId);
}

void AppController::moveDownInQueue(const QString &downloadId) {
    m_queue->moveDown(downloadId);
}

void AppController::moveFileToDesktop(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

    const QString sourceFile = item->savePath() + QStringLiteral("/") + item->filename();
    const QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    QString destFile = desktopPath + QStringLiteral("/") + item->filename();

    // If file already exists on desktop, add a number
    if (QFile::exists(destFile)) {
        const QString base = QFileInfo(item->filename()).completeBaseName();
        const QString ext = QFileInfo(item->filename()).suffix();
        const QString dotExt = ext.isEmpty() ? QString{} : QStringLiteral(".") + ext;

        int n = 2;
        while (n < 1000 && QFile::exists(destFile)) {
            destFile = desktopPath + QStringLiteral("/") + base + QStringLiteral(" (") + QString::number(n) + QStringLiteral(")") + dotExt;
            ++n;
        }
    }

    // Copy file to desktop
    if (QFile::copy(sourceFile, destFile)) {
        qDebug() << "File moved to desktop:" << destFile;
    } else {
        qDebug() << "Failed to move file to desktop";
    }
}

QString AppController::generateId() const {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void AppController::watchItem(DownloadItem *item) {
    // Schedule a debounced save on any meaningful state change
    const QString id = item->id();
    auto sched = [this, id]() { scheduleSave(id); };
    connect(item, &DownloadItem::statusChanged,    this, sched);
    connect(item, &DownloadItem::totalBytesChanged, this, sched);
    connect(item, &DownloadItem::doneBytesChanged,  this, sched);
    connect(item, &DownloadItem::resumeCapableChanged, this, sched);
    connect(item, &DownloadItem::savePathChanged,   this, sched);
    connect(item, &DownloadItem::filenameChanged,   this, sched);
}

void AppController::scheduleSave(const QString &id) {
    m_dirtyIds.insert(id);
    if (!m_saveTimer->isActive())
        m_saveTimer->start();
}

void AppController::flushDirty() {
    const auto items = m_queue->items();
    for (DownloadItem *item : items) {
        if (m_dirtyIds.contains(item->id()))
            m_db->save(item);
    }
    m_dirtyIds.clear();
}

void AppController::createQueue(const QString &name)
{
    if (name.trimmed().isEmpty()) return;
    QString queueId = QStringLiteral("queue-") + QString::number(QDateTime::currentMSecsSinceEpoch());
    Queue *q = new Queue(queueId, this);
    q->setName(name);
    q->setIsDownloadQueue(true);
    m_queueModel->addQueue(q);
    m_queueDb->save(q);
}

void AppController::deleteQueue(const QString &queueId)
{
    if (queueId == QStringLiteral("main-download")) return; // protect main queue
    m_queueDb->remove(queueId);
    m_queueModel->removeQueue(queueId);
}

void AppController::saveQueues()
{
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q) m_queueDb->save(q);
    }
    m_queueDb->flush();
}

void AppController::startQueue(const QString &queueId)
{
    Queue *q = m_queueModel->queueById(queueId);
    if (!q || queueId == QStringLiteral("download-limits")) return;

    // Mark as recently run for periodic schedules
    m_lastQueueRun[queueId] = QDateTime::currentDateTime();

    // Enqueue all pending downloads assigned to this queue
    int startedCount = 0;
    for (DownloadItem *item : m_queue->items()) {
        if (item->queueId() == queueId && item->status() == QStringLiteral("Paused")) {
            m_queue->resume(item->id());
            ++startedCount;
        }
    }

    qDebug() << "Starting queue" << queueId << q->name() << "- enqueued" << startedCount << "downloads";
}

void AppController::stopQueue(const QString &queueId)
{
    Queue *q = m_queueModel->queueById(queueId);
    if (!q || queueId == QStringLiteral("download-limits")) return;

    // Pause all actively downloading items in this queue
    int stoppedCount = 0;
    for (DownloadItem *item : m_queue->items()) {
        if (item->queueId() == queueId &&
            (item->status() == QStringLiteral("Downloading") ||
             item->status() == QStringLiteral("Queued"))) {
            m_queue->pause(item->id());
            ++stoppedCount;
        }
    }

    qDebug() << "Stopping queue" << queueId << q->name() << "- paused" << stoppedCount << "downloads";
}

int AppController::minutesUntilNextQueue() const
{
    return calculateMinutesUntilNextQueue();
}

int AppController::calculateMinutesUntilNextQueue() const
{
    int minutesMin = 999999;

    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (!q || q->id() == QStringLiteral("download-limits"))
            continue;

        // Check if this queue has a start time configured
        if (!q->hasStartTime())
            continue;

        // Try both HH:mm and HH:mm:ss AM/PM formats
        QTime scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm:ss AP"));
        if (!scheduleTime.isValid()) {
            scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm"));
        }
        if (!scheduleTime.isValid()) {
            continue;
        }

        QDateTime now = QDateTime::currentDateTime();
        QDateTime nextRun;

        if (q->startOnce()) {
            // One-time schedule: next run is today at the specified time
            nextRun = QDateTime(now.date(), scheduleTime);
            if (nextRun <= now) {
                // Time has passed today, no more runs for this queue
                continue;
            }
        } else if (q->startDaily()) {
            // Daily schedule: check if today is in the startDays list
            QStringList days = q->startDays();
            QString todayName = now.toString(QStringLiteral("dddd")).toLower();
            QString dayAbbrev = todayName.left(3).toLower();  // "mon", "tue", etc.

            bool shouldRunToday = false;
            for (const QString &day : days) {
                if (day.toLower().startsWith(dayAbbrev)) {
                    shouldRunToday = true;
                    break;
                }
            }

            if (shouldRunToday) {
                nextRun = QDateTime(now.date(), scheduleTime);
                if (nextRun <= now) {
                    // Time has passed today, check tomorrow
                    nextRun = nextRun.addDays(1);
                    // Check if tomorrow is in the schedule
                    QString tomorrowName = nextRun.toString(QStringLiteral("dddd")).toLower();
                    QString tomorrowAbbrev = tomorrowName.left(3).toLower();
                    bool tomorrowIsScheduled = false;
                    for (const QString &day : days) {
                        if (day.toLower().startsWith(tomorrowAbbrev)) {
                            tomorrowIsScheduled = true;
                            break;
                        }
                    }
                    if (!tomorrowIsScheduled)
                        continue;
                }
            } else {
                // Today is not a scheduled day, find next scheduled day
                for (int d = 1; d <= 7; ++d) {
                    QDateTime candidate = now.addDays(d);
                    QString dayName = candidate.toString(QStringLiteral("dddd")).toLower();
                    QString dayAbb = dayName.left(3).toLower();
                    bool isScheduled = false;
                    for (const QString &day : days) {
                        if (day.toLower().startsWith(dayAbb)) {
                            isScheduled = true;
                            break;
                        }
                    }
                    if (isScheduled) {
                        nextRun = QDateTime(candidate.date(), scheduleTime);
                        break;
                    }
                }
                if (!nextRun.isValid())
                    continue;
            }
        } else {
            // Periodic schedule (synchronization queue)
            if (!q->hasStartAgainEvery())
                continue;

            int intervalSecs = q->startAgainEveryHours() * 3600 + q->startAgainEveryMins() * 60;
            if (intervalSecs <= 0)
                continue;

            // Get last run time or use now if never run
            QDateTime lastRun = m_lastQueueRun.value(q->id(), now.addSecs(-intervalSecs));
            nextRun = lastRun.addSecs(intervalSecs);

            if (nextRun <= now) {
                // Time to run this periodic queue now
                minutesMin = 0;
                continue;
            }
        }

        // Calculate minutes until this queue should run
        if (nextRun.isValid()) {
            int mins = now.secsTo(nextRun) / 60;
            if (mins >= 0 && mins < minutesMin)
                minutesMin = mins;
        }
    }

    return minutesMin == 999999 ? 0 : minutesMin;
}

void AppController::checkQueueSchedules()
{
    int prevMinutes = calculateMinutesUntilNextQueue();

    QDateTime now = QDateTime::currentDateTime();

    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (!q || q->id() == QStringLiteral("download-limits"))
            continue;

        if (!q->hasStartTime())
            continue;

        // Try both HH:mm:ss AM/PM and HH:mm formats
        QTime scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm:ss AP"));
        if (!scheduleTime.isValid()) {
            scheduleTime = QTime::fromString(q->startTime(), QStringLiteral("HH:mm"));
        }
        if (!scheduleTime.isValid())
            continue;

        bool shouldStart = false;

        if (q->startOnce()) {
            // One-time schedule
            QDateTime nextRun = QDateTime(now.date(), scheduleTime);
            // Allow a 5-minute window (2.5 before and after)
            if (nextRun >= now.addSecs(-300) && nextRun <= now.addSecs(300)) {
                shouldStart = true;
            }
        } else if (q->startDaily()) {
            // Daily schedule: check if today is in the list
            QStringList days = q->startDays();
            QString todayName = now.toString(QStringLiteral("dddd")).toLower();
            QString dayAbbrev = todayName.left(3).toLower();

            bool isDayMatch = false;
            for (const QString &day : days) {
                if (day.toLower().startsWith(dayAbbrev)) {
                    isDayMatch = true;
                    break;
                }
            }

            if (isDayMatch) {
                int nowMins = now.time().hour() * 60 + now.time().minute();
                int scheduleMins = scheduleTime.hour() * 60 + scheduleTime.minute();
                // Start if within 5 minutes of scheduled time (wider tolerance for missed checks)
                if (qAbs(nowMins - scheduleMins) <= 2) {
                    shouldStart = true;
                }
            }
        } else {
            // Periodic (synchronization queue)
            if (!q->hasStartAgainEvery())
                continue;

            int intervalSecs = q->startAgainEveryHours() * 3600 + q->startAgainEveryMins() * 60;
            if (intervalSecs <= 0)
                continue;

            QDateTime lastRun = m_lastQueueRun.value(q->id(), now.addSecs(-intervalSecs - 300));
            QDateTime nextRun = lastRun.addSecs(intervalSecs);

            if (nextRun <= now && now.secsTo(nextRun) > -300) {
                shouldStart = true;
            }
        }

        if (shouldStart) {
            startQueue(q->id());
        }

        // Check if queue should stop
        if (q->hasStopTime()) {
            QTime stopTime = QTime::fromString(q->stopTime(), QStringLiteral("HH:mm"));
            if (stopTime.isValid()) {
                int nowMins = now.time().hour() * 60 + now.time().minute();
                int stopMins = stopTime.hour() * 60 + stopTime.minute();
                if (qAbs(nowMins - stopMins) <= 2) {
                    stopQueue(q->id());
                }
            }
        }
    }

    int currentMinutes = calculateMinutesUntilNextQueue();
    if (currentMinutes != prevMinutes) {
        emit minutesUntilNextQueueChanged();
    }
}
