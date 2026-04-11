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
#include <QtConcurrent>
#include <QLocalServer>
#include <QLocalSocket>
#include <QUuid>
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDesktopServices>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QDebug>
#include "AppSettings.h"
#include "DownloadQueue.h"
#include "DownloadTableModel.h"
#include "CategoryModel.h"
#include "NativeMessagingHost.h"
#include "SystemTrayIcon.h"
#include "DownloadDatabase.h"
#include "GrabberCrawler.h"
#include "GrabberProjectModel.h"
#include "GrabberResultModel.h"
#include "QueueDatabase.h"
#include "QueueModel.h"
#if defined(STELLAR_WINDOWS)
#  include <windows.h>
#endif
#include <QUrl>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QClipboard>
#include <QProcess>
#include <QTimer>
#include <QRegularExpression>
#include <QVersionNumber>
#include <QCryptographicHash>
#include <Queue.h>

namespace {
constexpr int kMinimumUpdateCheckIndicatorMs = 3000;
}

void AppController::checkUrl(const QString &url, QJSValue callback) {
    QNetworkRequest request(QUrl::fromUserInput(url));
    const QString customUserAgent = m_settings ? m_settings->customUserAgent().trimmed() : QString();
    const QString resolvedUserAgent =
        (m_settings && m_settings->useCustomUserAgent() && !customUserAgent.isEmpty())
        ? customUserAgent
        : QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION));
    request.setHeader(QNetworkRequest::UserAgentHeader, resolvedUserAgent);
    QNetworkReply *reply = m_nam->head(request);
    connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
        bool ok = (reply->error() == QNetworkReply::NoError);
        if (callback.isCallable()) {
            QJSValueList args;
            args << ok;
            callback.call(args);
        }
        reply->deleteLater();
    });
}

AppController::~AppController() {
    // Flush any pending debounced DB write before the object is destroyed.
    if (m_db) m_db->flush();
}

AppController::AppController(QObject *parent) : QObject(parent) {
    // ── 1. Components ────────────────────────────────────────────────────────────
    m_nam           = new QNetworkAccessManager(this);
    m_settings      = new AppSettings(this);
    DownloadItem::configureDateTimeFormat(
        m_settings->lastTryDateStyle(),
        m_settings->lastTryUse24Hour(),
        m_settings->lastTryShowSeconds());
    m_queue         = new DownloadQueue(this);
    m_downloadModel = new DownloadTableModel(this);
    m_categoryModel = new CategoryModel(this);
    m_grabberProjectModel = new GrabberProjectModel(this);
    m_grabberResultModel = new GrabberResultModel(this);
    m_grabberCrawler = new GrabberCrawler(m_nam, this);
    m_nativeHost    = new NativeMessagingHost(this);
    m_tray          = new SystemTrayIcon(this);
    m_db            = new DownloadDatabase(this);
    m_queueDb       = new QueueDatabase(this);
    m_queueModel    = new QueueModel(this);
    m_saveTimer     = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(500);
    connect(m_saveTimer, &QTimer::timeout, this, &AppController::flushDirty);
    m_recentErrorTimer = new QTimer(this);
    m_recentErrorTimer->setInterval(30000);
    connect(m_recentErrorTimer, &QTimer::timeout, this, &AppController::pruneRecentErrorDownloads);
    m_recentErrorTimer->start();
    m_grabberPersistTimer = new QTimer(this);
    m_grabberPersistTimer->setSingleShot(true);
    m_grabberPersistTimer->setInterval(400);
    connect(m_grabberPersistTimer, &QTimer::timeout, this, &AppController::persistActiveGrabberResults);

    // Forward the queue's active-count change so the QML property App.activeDownloads
    // emits its NOTIFY signal and toolbar/statusbar bindings re-evaluate reactively.
    // Without this connection, activeDownloadsChanged() was declared but never emitted,
    // so "Stop All" never grayed out when all downloads finished.
    connect(m_queue, &DownloadQueue::activeCountChanged,
            this,    &AppController::activeDownloadsChanged);

    // Update tray tooltip every 2 seconds with live download stats.
    // Done in C++ rather than QML so the tray always reflects current state
    // even when no QML binding has re-evaluated recently.
    m_tooltipTimer = new QTimer(this);
    m_tooltipTimer->setInterval(2000);
    connect(m_tooltipTimer, &QTimer::timeout, this, [this] {
        qint64 totalSpeed = 0;
        for (DownloadItem *item : m_downloadModel->allItems())
            totalSpeed += item->speed();

        const int total  = m_downloadModel->allItems().size();
        const int active = m_queue->activeCount();

        QString tip = QStringLiteral("Stellar Download Manager v") + appVersion();
        if (active > 0) {
            if (totalSpeed >= 1024LL * 1024)
                tip += QStringLiteral("\nSpeed: %1 MB/s").arg(double(totalSpeed) / (1024.0 * 1024.0), 0, 'f', 1);
            else
                tip += QStringLiteral("\nSpeed: %1 KB/s").arg(double(totalSpeed) / 1024.0, 0, 'f', 0);
        }
        tip += QStringLiteral("\nDownloads: %1   Running: %2").arg(total).arg(active);
        if (m_tray) m_tray->setToolTip(tip);
    });
    m_tooltipTimer->start();

    // ── 2. IPC Server ──────────────────────────────────────────────────────────
    m_ipcServer = new QLocalServer(this);
    if (!m_ipcServer->listen(QStringLiteral("StellarDownloadManager"))) {
        qDebug() << "[IPC] FAILED to listen on StellarDownloadManager";
    }

    connect(m_ipcServer, &QLocalServer::newConnection, this, [this]() {
        QLocalSocket *sock = m_ipcServer->nextPendingConnection();
        if (!sock) return;
        connect(sock, &QLocalSocket::readyRead, this, [this, sock]() {
            const QByteArray data = sock->readAll();
            const QJsonObject obj = QJsonDocument::fromJson(data).object();
            if (obj.isEmpty()) return;
            const QString type = obj.value(QStringLiteral("type")).toString();
            if (type == QStringLiteral("download")) {
                const QString url       = obj.value(QStringLiteral("url")).toString();
                const QString name      = obj.value(QStringLiteral("filename")).toString();
                const QString cookies   = obj.value(QStringLiteral("cookies")).toString();
                const QString referrer  = obj.value(QStringLiteral("referrer")).toString();
                const QString pageUrl   = obj.value(QStringLiteral("pageUrl")).toString();
                if (m_settings->startImmediately()) {
                    addUrl(url, {}, {}, {}, true, cookies, referrer, pageUrl);
                    emit showWindowRequested();
                } else {
                    if (!cookies.isEmpty()) m_pendingCookies[url] = cookies;
                    if (!referrer.isEmpty()) m_pendingReferrers[url] = referrer;
                    if (!pageUrl.isEmpty()) m_pendingPageUrls[url] = pageUrl;
                    emit showWindowRequested();
                    emit interceptedDownloadRequested(url, name);
                }
                sock->deleteLater();
            } else if (type == QStringLiteral("focus")) {
                emit showWindowRequested();
                sock->deleteLater();
            }
        });
        connect(sock, &QLocalSocket::disconnected, sock, &QLocalSocket::deleteLater);
    });

    // ── 3. Data & Setup ────────────────────────────────────────────────────────
    if (m_queueDb->open()) {
        const auto queues = m_queueDb->loadAll(this);
        for (Queue *q : queues) m_queueModel->addQueue(q);
    }
    
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
        syncQueue->setIsDownloadQueue(false);
        m_queueModel->addQueue(syncQueue);
        m_queueDb->save(syncQueue);
    }
    if (m_queueModel->queueById("download-limits") == nullptr) {
        Queue *limitsQueue = new Queue("download-limits", this);
        limitsQueue->setName("Download Limits");
        limitsQueue->setIsDownloadQueue(false);
        m_queueModel->addQueue(limitsQueue);
        m_queueDb->save(limitsQueue);
    }

    // ── 4. Connections ──────────────────────────────────────────────────────────
    m_queue->setNam(m_nam);
    m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps());
    m_queue->setCustomUserAgentEnabled(m_settings->useCustomUserAgent());
    m_queue->setCustomUserAgent(m_settings->customUserAgent());
    m_queue->setTemporaryDirectory(m_settings->temporaryDirectory());
    m_queue->setCanStartPredicate([this](DownloadItem *item) {
        return canStartDownloadItem(item);
    });
    cleanupTemporaryDirectory();
    connect(m_settings, &AppSettings::globalSpeedLimitKBpsChanged, this, [this]() {
        m_queue->setSpeedLimitKBps(m_settings->globalSpeedLimitKBps());
    });
    auto refreshDateFormatting = [this]() {
        DownloadItem::configureDateTimeFormat(
            m_settings->lastTryDateStyle(),
            m_settings->lastTryUse24Hour(),
            m_settings->lastTryShowSeconds());
        for (DownloadItem *item : m_downloadModel->allItems()) {
            if (item)
                item->refreshDateStrings();
        }
    };
    connect(m_settings, &AppSettings::lastTryDateStyleChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::lastTryUse24HourChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::lastTryShowSecondsChanged, this, refreshDateFormatting);
    connect(m_settings, &AppSettings::autoCheckUpdatesChanged, this, [this]() {
        if (!m_settings->autoCheckUpdates()) {
            if (m_updateAvailable) {
                m_updateAvailable = false;
                emit updateAvailableChanged();
            }
            if (!m_updateStatusText.isEmpty()) {
                m_updateStatusText.clear();
                emit updateStatusTextChanged();
            }
        }
    });
    connect(m_settings, &AppSettings::useCustomUserAgentChanged, this, [this]() {
        m_queue->setCustomUserAgentEnabled(m_settings->useCustomUserAgent());
    });
    connect(m_settings, &AppSettings::customUserAgentChanged, this, [this]() {
        m_queue->setCustomUserAgent(m_settings->customUserAgent());
    });
    connect(m_settings, &AppSettings::temporaryDirectoryChanged, this, [this]() {
        m_queue->setTemporaryDirectory(m_settings->temporaryDirectory());
        cleanupTemporaryDirectory();
    });

    // ── Clipboard URL monitoring ───────────────────────────────────────────────
    // When enabled, watch the system clipboard for URLs whose file extensions
    // match the user's monitored extension list (same list as browser interception).
    // We keep track of the last URL we already emitted so repeated clipboard
    // events for the same content don't open multiple dialogs.
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, [this]() {
        // Skip if the feature is disabled
        if (!m_settings->clipboardMonitorEnabled()) return;

        const QString text = QGuiApplication::clipboard()->text().trimmed();
        if (text.isEmpty()) return;
        // Avoid re-firing for the same clipboard content
        if (text == m_lastClipboardUrl) return;

        // Only react to valid http/https URLs
        QUrl url(text);
        if (!url.isValid() || (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https")))
            return;

        // Extract the file extension from the URL path (ignore query / fragment)
        const QString path = url.path();
        const int dotIdx = path.lastIndexOf('.');
        if (dotIdx < 0) return;
        const QString ext = path.mid(dotIdx + 1).toLower();
        if (ext.isEmpty()) return;

        // Check against the monitored extensions list (same as browser integration)
        if (!m_settings->monitoredExtensions().contains(ext, Qt::CaseInsensitive)) return;

        m_lastClipboardUrl = text;
        emit clipboardUrlDetected(text);
    });
    // Grabber status is surfaced as simple properties so the wizard can stay
    // declarative and only react to high-level crawl lifecycle changes.
    connect(m_grabberCrawler, &GrabberCrawler::progressChanged, this, [this](const QString &statusText) {
        if (m_grabberStatusText == statusText)
            return;
        m_grabberStatusText = statusText;
        emit grabberStatusTextChanged();
        static const QRegularExpression pagesRe(QStringLiteral(R"(across\s+(\d+)\s+pages)"), QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression foundRe(QStringLiteral(R"(Found\s+(\d+)\s+files)"), QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch pagesMatch = pagesRe.match(statusText);
        if (pagesMatch.hasMatch()) {
            m_grabberPagesProcessed = pagesMatch.captured(1).toInt();
            m_grabberAdvancedPagesProcessed = m_grabberPagesProcessed;
        }
        const QRegularExpressionMatch foundMatch = foundRe.match(statusText);
        if (foundMatch.hasMatch())
            m_grabberMatchedFiles = foundMatch.captured(1).toInt();
    });
    connect(m_grabberCrawler, &GrabberCrawler::resultFound, this, [this](const QVariantMap &result) {
        m_grabberResultModel->appendResult(result);
        m_grabberMatchedFiles = m_grabberResultModel->rowCount();
        scheduleGrabberResultsPersist();
    });
    connect(m_grabberCrawler, &GrabberCrawler::resultMetadataUpdated, this, [this](const QString &url, qint64 sizeBytes) {
        m_grabberResultModel->updateResultSize(url, sizeBytes);
        scheduleGrabberResultsPersist();
    });
    connect(m_grabberCrawler, &GrabberCrawler::finished, this, [this](const QVariantList &results) {
        m_grabberBusy = false;
        emit grabberBusyChanged();
        m_grabberResultModel->setResults(results);
        m_grabberMatchedFiles = results.size();
        if (!m_activeGrabberProjectId.isEmpty()) {
            QVariantMap project = m_grabberProjectModel->projectDataById(m_activeGrabberProjectId);
            if (!project.isEmpty()) {
                project[QStringLiteral("lastResults")] = results;
                project[QStringLiteral("lastResultCount")] = results.size();
                project[QStringLiteral("lastExploreFinishedAt")] = QDateTime::currentDateTime().toString(Qt::ISODate);
                m_grabberProjectModel->upsertProject(project);
            }
            m_grabberProjectModel->updateProjectRunState(
                m_activeGrabberProjectId,
                QStringLiteral("Found %1 files").arg(results.size()),
                results.size());
        }
        emit grabberExploreFinished(m_activeGrabberProjectId);
    });
    connect(m_grabberCrawler, &GrabberCrawler::failed, this, [this](const QString &message) {
        m_grabberBusy = false;
        emit grabberBusyChanged();
        m_grabberStatusText = message;
        emit grabberStatusTextChanged();
        emit grabberError(message);
    });
    connect(m_queue, &DownloadQueue::itemAdded, this, [this](DownloadItem *item) {
        m_downloadModel->addItem(item);
        if (!m_restoring) { m_db->save(item); watchItem(item); }
    });
    connect(m_queue, &DownloadQueue::itemRemoved, this, [this](const QString &id) {
        // Check status before removal so we can keep the count accurate
        auto *item = m_downloadModel->itemById(id);
        if (item && item->statusEnum() == DownloadItem::Status::Completed) {
            m_completedCount--;
            emit completedDownloadsChanged();
        }
        m_downloadModel->removeItem(id);
        if (m_recentErrorDownloads.remove(id) > 0)
            emit recentErrorDownloadsChanged();
        m_dirtyIds.remove(id);
        m_db->remove(id);
    });
    connect(m_queue, &DownloadQueue::itemCompleted, this, [this](DownloadItem *item) {
        m_db->save(item);
        m_dirtyIds.remove(item->id());
        m_queueRetryCounts.remove(item->id());
        m_completedCount++;
        emit completedDownloadsChanged();
        if (item && !item->queueId().isEmpty()) {
            recordQueueTransferSample(item->queueId(), item->doneBytes());
            enforceQueueDownloadLimits(item->queueId());
            Queue *queue = m_queueModel ? m_queueModel->queueById(item->queueId()) : nullptr;
            if (queue) {
                bool queueFinished = true;
                for (DownloadItem *candidate : m_queue->items()) {
                    if (!candidate || candidate->queueId() != item->queueId())
                        continue;
                    if (candidate->statusEnum() == DownloadItem::Status::Queued
                        || candidate->statusEnum() == DownloadItem::Status::Downloading
                        || candidate->statusEnum() == DownloadItem::Status::Assembling) {
                        queueFinished = false;
                        break;
                    }
                }
                if (queueFinished) {
                    if (queue->openFileWhenDone() && !queue->openFilePath().isEmpty())
                        QDesktopServices::openUrl(QUrl::fromLocalFile(queue->openFilePath()));
                    if (queue->turnOffComputerWhenDone()) {
#if defined(Q_OS_WIN)
                        if (queue->forceProcessesToTerminate())
                            QProcess::startDetached(QStringLiteral("shutdown"),
                                                    { QStringLiteral("/s"), QStringLiteral("/f"), QStringLiteral("/t"), QStringLiteral("0") });
                        else
                            shutdownComputer();
#else
                        shutdownComputer();
#endif
                    }
                    if (queue->exitIDMWhenDone())
                        QCoreApplication::quit();
                }
            }
        }
        if (!m_pendingFileInfoDownloads.contains(item->id())
            && m_settings->showCompletionNotification()
            && m_tray
            && !isGrabberProjectId(item->category())) {
            const QString name = item->filename().isEmpty()
                ? item->url().fileName()
                : item->filename();
            m_tray->showNotification(QStringLiteral("Download Complete"), name);
        }
        if (!m_pendingFileInfoDownloads.contains(item->id()))
            emit downloadCompleted(item);

        if (item && item->id() == m_pendingUpdateDownloadId) {
            const QString installerPath = item->savePath() + QStringLiteral("/") + item->filename();
            QFile installerFile(installerPath);
            if (!installerFile.open(QIODevice::ReadOnly)) {
                emit updateError(QStringLiteral("Stellar downloaded the update, but could not read the installer file."));
            } else {
                const QByteArray actualHash = QCryptographicHash::hash(installerFile.readAll(), QCryptographicHash::Sha256).toHex();
                installerFile.close();
                if (!m_pendingUpdateSha256.trimmed().isEmpty()
                    && actualHash.compare(m_pendingUpdateSha256.trimmed().toUtf8(), Qt::CaseInsensitive) != 0) {
                    emit updateError(QStringLiteral("The downloaded update installer failed hash verification."));
                } else {
#if defined(Q_OS_WIN)
                    const QStringList args{
                        QStringLiteral("/VERYSILENT"),
                        QStringLiteral("/SUPPRESSMSGBOXES"),
                        QStringLiteral("/NOCANCEL"),
                        QStringLiteral("/CLOSEAPPLICATIONS"),
                        QStringLiteral("/FORCECLOSEAPPLICATIONS"),
                        QStringLiteral("/RESTARTAPPLICATIONS")
                    };
                    if (QProcess::startDetached(installerPath, args))
                        QCoreApplication::quit();
                    else
                        emit updateError(QStringLiteral("Stellar downloaded the update, but could not launch the installer."));
#endif
                }
            }
            m_pendingUpdateDownloadId.clear();
            m_pendingUpdateInstallerPath.clear();
            m_pendingUpdateSha256.clear();
        }
    });
    connect(m_queue, &DownloadQueue::itemFailed, this, [this](DownloadItem *item, const QString &reason) {
        if (!item)
            return;
        m_recentErrorDownloads[item->id()] = QDateTime::currentDateTime();
        emit recentErrorDownloadsChanged();
        m_db->save(item);
        m_dirtyIds.remove(item->id());
        Queue *queue = (!item->queueId().isEmpty() && m_queueModel)
            ? m_queueModel->queueById(item->queueId())
            : nullptr;
        if (queue && queue->hasMaxRetries()) {
            const int retries = m_queueRetryCounts.value(item->id(), 0);
            if (retries < queue->maxRetries()) {
                m_queueRetryCounts[item->id()] = retries + 1;
                QTimer::singleShot(1000, this, [this, id = item->id()]() {
                    DownloadItem *retryItem = m_downloadModel->itemById(id);
                    if (!retryItem || retryItem->statusEnum() != DownloadItem::Status::Error)
                        return;
                    retryItem->setStatus(DownloadItem::Status::Queued);
                    scheduleSave(id);
                    m_queue->scheduleNext();
                });
                return;
            }
        }
        m_queueRetryCounts.remove(item->id());
        if (!item->queueId().isEmpty() && item->doneBytes() > 0) {
            recordQueueTransferSample(item->queueId(), item->doneBytes());
            enforceQueueDownloadLimits(item->queueId());
        }
        if (!m_pendingFileInfoDownloads.contains(item->id())
            && m_settings->showErrorNotification()
            && m_tray) {
            const QString name = item->filename().isEmpty()
                ? item->url().fileName()
                : item->filename();
            const QString details = reason.isEmpty() ? QStringLiteral("The download failed.") : reason;
            m_tray->showNotification(QStringLiteral("Download Failed"), QStringLiteral("%1\n%2").arg(name, details));
        }
    });
    connect(m_nativeHost, &NativeMessagingHost::downloadRequested, this, [this](const QString &url, const QString &filename, const QString &referrer, const QString &cookies, int modifierKey) {
        Q_UNUSED(filename);
        // Skip interception if bypass modifier key is active and matches user's configured key
        if (modifierKey > 0 && modifierKey == m_settings->bypassInterceptKey()) {
            return;  // Let the browser download the file
        }
        addUrl(url, {}, {}, {}, true, cookies, referrer);
    });
    connect(m_tray, &SystemTrayIcon::showRequested,        this, &AppController::showWindowRequested);
    connect(m_tray, &SystemTrayIcon::quitRequested,        &QCoreApplication::quit);
    connect(m_tray, &SystemTrayIcon::addUrlRequested,      this, [this]() { emit showWindowRequested(); });
    connect(m_tray, &SystemTrayIcon::githubRequested,       this, &AppController::trayGithubRequested);
    connect(m_tray, &SystemTrayIcon::aboutRequested,        this, &AppController::trayAboutRequested);
    connect(m_tray, &SystemTrayIcon::speedLimiterRequested, this, &AppController::traySpeedLimiterRequested);
    connect(m_tray, &SystemTrayIcon::contextMenuRequested,  this, &AppController::contextMenuRequested);
    
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this]() {
        flushDirty();
    });
    if (m_settings->autoCheckUpdates()) {
        QTimer::singleShot(2500, this, [this]() {
            checkForUpdates(false);
        });
    }

    // ── 5. Finalization ──────────────────────────────────────────────────────────
    QString err = registerNativeHost();
    if (err.isEmpty()) qDebug() << "[NativeHost] registered OK";
    else qDebug() << "[NativeHost] registration FAILED:" << err;

    m_tray->show();

    if (m_db->open()) {
        m_restoring = true;
        const auto items = m_db->loadAll();
        for (int i = 0; i < items.size(); ++i) {
            QTimer::singleShot(i * 16, this, [this, item = items.at(i)]() {
                m_queue->enqueueRestored(item);
                watchItem(item);
            });
        }
        QTimer::singleShot(items.size() * 16 + 50, this, [this]() {
            m_restoring = false;
            // Count completed downloads from the restored items
            m_completedCount = 0;
              for (auto *item : m_downloadModel->allItems())
                  if (item->statusEnum() == DownloadItem::Status::Completed)
                      m_completedCount++;
              emit completedDownloadsChanged();
              checkQueueSchedules();
              for (int i = 0; i < m_queueModel->rowCount(); ++i) {
                  Queue *queue = m_queueModel->queueAt(i);
                  if (queue && queue->startOnIDMStartup() && queue->id() != QStringLiteral("download-limits"))
                      startQueue(queue->id());
              }
              if (m_settings->speedLimiterOnStartup() && m_settings->globalSpeedLimitKBps() == 0
                      && m_settings->savedSpeedLimitKBps() > 0) {
                  m_settings->setGlobalSpeedLimitKBps(m_settings->savedSpeedLimitKBps());
            }
        });
      } else {
          checkQueueSchedules();
          for (int i = 0; i < m_queueModel->rowCount(); ++i) {
              Queue *queue = m_queueModel->queueAt(i);
              if (queue && queue->startOnIDMStartup() && queue->id() != QStringLiteral("download-limits"))
                  startQueue(queue->id());
          }
          if (m_settings->speedLimiterOnStartup() && m_settings->globalSpeedLimitKBps() == 0
                  && m_settings->savedSpeedLimitKBps() > 0) {
              m_settings->setGlobalSpeedLimitKBps(m_settings->savedSpeedLimitKBps());
        }
    }
}

int AppController::activeDownloads() const {
    return m_queue->activeCount();
}

void AppController::setSelectedCategory(const QString &v) {
    if (m_selectedCategory != v) {
        m_selectedCategory = v;
        m_selectedQueue = QString();
        m_downloadModel->setFilterCategory(v);
        emit selectedCategoryChanged();
    }
}

void AppController::setSelectedQueue(const QString &v) {
    if (m_selectedQueue != v) {
        m_selectedQueue = v;
        m_selectedCategory = QString();
        m_downloadModel->setFilterQueue(v);
        emit selectedQueueChanged();
    }
}

DownloadItem *AppController::createDownloadItem(const QString &url, const QString &savePath,
                                                const QString &category, const QString &description,
                                                bool startNow, const QString &cookies,
                                                const QString &referrer, const QString &parentUrl,
                                                const QString &username, const QString &password,
                                                const QString &filenameOverride, const QString &queueId,
                                                bool emitUiSignal) {
    if (url.trimmed().isEmpty())
        return nullptr;

    const QString id = generateId();
    const QUrl qurl = QUrl::fromUserInput(url);
    auto *item = new DownloadItem(id, qurl);

    if (!filenameOverride.isEmpty()) {
        item->setFilename(filenameOverride);
        item->setFilenameManuallySet(true);
    }

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
    if (!queueId.isEmpty())
        item->setQueueId(queueId);

    if (!savePath.isEmpty()) {
        item->setSavePath(savePath);
    } else if (m_settings->defaultSavePath().isEmpty()) {
        item->setSavePath(m_categoryModel->savePathForCategory(resolvedCategory));
    } else {
        item->setSavePath(m_settings->defaultSavePath());
    }

    if (startNow)
        m_queue->enqueue(item);
    else
        m_queue->enqueueHeld(item);

    if (emitUiSignal)
        emit downloadAdded(item);
    return item;
}

void AppController::addUrl(const QString &url, const QString &savePath,
                           const QString &category, const QString &description,
                           bool startNow, const QString &cookies,
                           const QString &referrer, const QString &parentUrl,
                           const QString &username, const QString &password,
                           const QString &filenameOverride, const QString &queueId) {
    createDownloadItem(url, savePath, category, description, startNow, cookies,
                       referrer, parentUrl, username, password, filenameOverride,
                       queueId, true);
}

QString AppController::beginPendingDownload(const QString &url,
                                            const QString &filenameOverride,
                                            const QString &cookies,
                                            const QString &referrer,
                                            const QString &parentUrl,
                                            const QString &username,
                                            const QString &password) {
    const QString tempDir = m_settings->temporaryDirectory().trimmed();
    DownloadItem *item = createDownloadItem(url, tempDir, {}, {}, true, cookies, referrer,
                                            parentUrl, username, password,
                                            filenameOverride, {}, false);
    if (!item)
        return {};
    m_pendingFileInfoDownloads.insert(item->id());
    return item->id();
}

bool AppController::finalizePendingDownload(const QString &downloadId,
                                            const QString &fullSavePath,
                                            const QString &category,
                                            const QString &description,
                                            bool startNow,
                                            const QString &queueId) {
    DownloadItem *item = m_downloadModel->itemById(downloadId);
    if (!item)
        return false;

    const int sep = qMax(fullSavePath.lastIndexOf(QLatin1Char('/')),
                         fullSavePath.lastIndexOf(QLatin1Char('\\')));
    const QString newSaveDir = sep >= 0 ? fullSavePath.left(sep) : item->savePath();
    const QString newFilename = sep >= 0 ? fullSavePath.mid(sep + 1) : item->filename();
    const QString resolvedCategory = category.isEmpty()
        ? m_categoryModel->categoryForUrl(item->url(), newFilename)
        : category;

    if (item->statusEnum() == DownloadItem::Status::Completed) {
        if (!moveDownloadFile(downloadId, fullSavePath))
            return false;
    } else {
        if (!m_queue->relocateDownload(downloadId, newSaveDir, newFilename))
            return false;
    }

    item->setFilenameManuallySet(true);
    item->setCategory(resolvedCategory);
    item->setDescription(description);
    item->setQueueId(queueId);
    scheduleSave(downloadId);

    if (startNow) {
        if (item->statusEnum() == DownloadItem::Status::Paused)
            m_queue->resume(downloadId);
        m_pendingFileInfoDownloads.remove(downloadId);
        if (item->statusEnum() == DownloadItem::Status::Completed)
            emit downloadCompleted(item);
        else
            emit downloadAdded(item);
    } else {
        if (item->statusEnum() == DownloadItem::Status::Downloading
            || item->statusEnum() == DownloadItem::Status::Queued
            || item->statusEnum() == DownloadItem::Status::Assembling) {
            m_queue->pause(downloadId);
        }
    }
    return true;
}

void AppController::discardPendingDownload(const QString &downloadId) {
    if (downloadId.isEmpty())
        return;
    m_pendingFileInfoDownloads.remove(downloadId);
    m_queue->cancel(downloadId);
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

bool AppController::fileExists(const QString &path) const {
    return QFileInfo::exists(path);
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
    // Windows: return the Firefox manifest path for diagnostics/UI.
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
    const QString chromeManifestPath = QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json"));
    lines << QStringLiteral("Chrome manifest path: ") + chromeManifestPath;
    lines << QStringLiteral("Chrome manifest exists: ")
          + (QFile::exists(chromeManifestPath) ? QStringLiteral("YES") : QStringLiteral("NO"));

    const QList<QPair<QString, QString>> regKeys = {
        { QStringLiteral("Chrome"),  QStringLiteral("Software\\Google\\Chrome\\NativeMessagingHosts\\com.stellar.downloadmanager") },
        { QStringLiteral("Firefox"), QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager") }
    };

    for (const auto &entry : regKeys) {
        HKEY hKey = nullptr;
        LONG res = RegOpenKeyExW(HKEY_CURRENT_USER,
                                 reinterpret_cast<LPCWSTR>(entry.second.utf16()),
                                 0, KEY_QUERY_VALUE, &hKey);
        if (res != ERROR_SUCCESS) {
            lines << entry.first + QStringLiteral(" registry key: NOT FOUND (error %1)").arg(res);
            continue;
        }
        WCHAR buf[MAX_PATH] = {};
        DWORD sz = sizeof(buf);
        DWORD type = 0;
        res = RegQueryValueExW(hKey, L"", nullptr, &type,
                               reinterpret_cast<LPBYTE>(buf), &sz);
        RegCloseKey(hKey);
        if (res == ERROR_SUCCESS)
            lines << entry.first + QStringLiteral(" registry value: ") + QString::fromWCharArray(buf);
        else
            lines << entry.first + QStringLiteral(" registry default value: NOT SET (error %1)").arg(res);
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
    manifest[QStringLiteral("allowed_origins")] = QJsonArray{ QStringLiteral("chrome-extension://kncomdlgkcaamlaaoloncdafbijdfcjo/") };

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
    const QString chromeManifestPath = QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json"));

    QJsonObject firefoxManifest;
    firefoxManifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    firefoxManifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    firefoxManifest[QStringLiteral("path")]        = exePath;
    firefoxManifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    firefoxManifest[QStringLiteral("allowed_extensions")] = QJsonArray{ QStringLiteral("stellar@stellar.moe") };

    QJsonObject chromeManifest;
    chromeManifest[QStringLiteral("name")]        = QStringLiteral("com.stellar.downloadmanager");
    chromeManifest[QStringLiteral("description")] = QStringLiteral("Stellar Download Manager native messaging host");
    chromeManifest[QStringLiteral("path")]        = exePath;
    chromeManifest[QStringLiteral("type")]        = QStringLiteral("stdio");
    chromeManifest[QStringLiteral("allowed_origins")] = QJsonArray{ QStringLiteral("chrome-extension://kncomdlgkcaamlaaoloncdafbijdfcjo/") };

    const QByteArray firefoxJson = QJsonDocument(firefoxManifest).toJson(QJsonDocument::Indented);
    const QByteArray chromeJson  = QJsonDocument(chromeManifest).toJson(QJsonDocument::Indented);

    QDir().mkpath(QCoreApplication::applicationDirPath());
    {
        QFile f(manifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write Firefox native host manifest: ") + manifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(firefoxJson);
    }
    {
        QFile f(chromeManifestPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return QStringLiteral("Could not write Chrome native host manifest: ") + chromeManifestPath
                   + QStringLiteral("\nError: ") + f.errorString();
        f.write(chromeJson);
    }
#endif

#if defined(STELLAR_WINDOWS)
    // Chrome and Firefox want different manifest schemas, so register each
    // browser against its own manifest file.
    const QList<QPair<QString, QString>> regTargets = {
        { QStringLiteral("Software\\Google\\Chrome\\NativeMessagingHosts\\com.stellar.downloadmanager"),
          QDir::toNativeSeparators(QCoreApplication::applicationDirPath() + QStringLiteral("/com.stellar.downloadmanager.chrome.json")) },
        { QStringLiteral("Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager"),
          manifestPath }
    };

    for (const auto &target : regTargets) {
        const std::wstring wval = reinterpret_cast<const wchar_t *>(target.second.utf16());
        HKEY hKey = nullptr;
        LONG res = RegCreateKeyExW(
            HKEY_CURRENT_USER,
            reinterpret_cast<LPCWSTR>(target.first.utf16()),
            0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
            &hKey, nullptr);
        if (res != ERROR_SUCCESS || !hKey) {
            return QStringLiteral("Failed to create native host registry key %1 (error %2).\nPlease register manually.")
                .arg(target.first, QString::number(res));
        }

        res = RegSetValueExW(
            hKey, L"", 0, REG_SZ,
            reinterpret_cast<const BYTE *>(wval.c_str()),
            static_cast<DWORD>((wval.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(hKey);

        if (res != ERROR_SUCCESS) {
            return QStringLiteral("Failed to write native host registry value %1 (error %2).\nPlease register manually.")
                .arg(target.first, QString::number(res));
        }
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
    QStringList toDelete;
    const auto items = m_downloadModel->allItems();
    for (auto *item : items) {
        if (item->status() == QStringLiteral("Completed"))
            toDelete << item->id();
    }
    if (toDelete.isEmpty()) return;
    m_downloadModel->beginBulkRemove();
    for (const QString &id : toDelete)
        deleteDownload(id, mode);
    m_downloadModel->endBulkRemove();
}

void AppController::deleteDownloads(const QStringList &ids, int mode) {
    if (ids.isEmpty()) return;
    const QStringList stableIds = ids;
    m_downloadModel->beginBulkRemove();
    for (const QString &id : stableIds)
        deleteDownload(id, mode);
    m_downloadModel->endBulkRemove();
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
    DownloadItem *item = m_downloadModel->itemById(id);
    const bool wasPendingFileInfoDownload = m_pendingFileInfoDownloads.remove(id);
    m_queue->resume(id);
    if (wasPendingFileInfoDownload && item && item->queueId().isEmpty())
        emit downloadAdded(item);
}

void AppController::redownload(const QString &id) {
    auto *item = m_downloadModel->itemById(id);
    if (!item) return;

    QString url = item->url().toString();
    QString savePath = item->savePath();
    QString category = item->category();
    QString description = item->description();
    QString cookies = item->cookies();
    QString referrer = item->referrer();
    QString parentUrl = item->parentUrl();
    QString username = item->username();
    QString password = item->password();

    m_queue->cancel(id);

    addUrl(url, savePath, category, description, true, cookies, referrer, parentUrl, username, password);
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

    if (!filePath.isEmpty()) {
        // Run file deletion on a thread pool thread — never block the UI for disk IO.
        const int capturedMode = mode;
        QtConcurrent::run([capturedMode, filePath]() {
            if (capturedMode == 2)
                QFile::moveToTrash(filePath);
            else
                QFile::remove(filePath);
        });
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

void AppController::setDownloadDescription(const QString &id, const QString &description) {
    auto *item = m_downloadModel->itemById(id);
    if (item) { item->setDescription(description); scheduleSave(id); }
}

bool AppController::moveDownloadFile(const QString &id, const QString &newFilePath) {
    auto *item = m_downloadModel->itemById(id);
    if (!item || item->status() != QStringLiteral("Completed")) return false;

    const QString oldPath = item->savePath() + QStringLiteral("/") + item->filename();
    const QFileInfo newInfo(newFilePath);
    const QString newDir = newInfo.absolutePath();
    const QString newName = newInfo.fileName();

    QDir().mkpath(newDir);
    if (!QFile::rename(oldPath, newFilePath)) {
        QFile src(oldPath);
        QFile dst(newFilePath);
        if (!src.open(QIODevice::ReadOnly) || !dst.open(QIODevice::WriteOnly))
            return false;
        const qint64 kChunk = 1024 * 1024;
        while (!src.atEnd()) {
            const QByteArray chunk = src.read(kChunk);
            if (chunk.isEmpty() && src.error() != QFile::NoError)
                return false;
            if (dst.write(chunk) != chunk.size())
                return false;
        }
        src.close();
        dst.close();
        QFile::remove(oldPath);
    }

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

QString AppController::updateMetadataUrl() {
    return QStringLiteral("https://raw.githubusercontent.com/Ninka-Rex/Stellar/refs/heads/master/update.json");
}

QString AppController::updateChangelogUrl() {
    return QStringLiteral("https://raw.githubusercontent.com/Ninka-Rex/Stellar/refs/heads/master/changelog.md");
}

void AppController::setCheckingForUpdates(bool checking) {
    if (m_checkingForUpdates == checking)
        return;
    m_checkingForUpdates = checking;
    emit checkingForUpdatesChanged();
}

void AppController::finishUpdateCheckUi(const std::function<void()> &finishWork) {
    const qint64 elapsed = m_updateCheckStartedAt.isValid()
        ? m_updateCheckStartedAt.msecsTo(QDateTime::currentDateTime())
        : kMinimumUpdateCheckIndicatorMs;
    const int remaining = qMax<qint64>(0, kMinimumUpdateCheckIndicatorMs - elapsed);
    QTimer::singleShot(remaining, this, [this, finishWork]() {
        setCheckingForUpdates(false);
        if (finishWork)
            finishWork();
    });
}

int AppController::compareVersionStrings(const QString &lhs, const QString &rhs) {
    QString normalizedLhs = lhs.trimmed();
    QString normalizedRhs = rhs.trimmed();
    normalizedLhs.remove(QRegularExpression(QStringLiteral("[^0-9\\.]")));
    normalizedRhs.remove(QRegularExpression(QStringLiteral("[^0-9\\.]")));
    const QVersionNumber lv = QVersionNumber::fromString(normalizedLhs);
    const QVersionNumber rv = QVersionNumber::fromString(normalizedRhs);
    return QVersionNumber::compare(lv, rv);
}

void AppController::applyUpdateMetadata(const QVariantMap &map, bool manual) {
    const QString version = map.value(QStringLiteral("version")).toString().trimmed();
    if (version.isEmpty()) {
        emit updateError(QStringLiteral("Update metadata is missing a version number."));
        return;
    }

    const bool available = compareVersionStrings(version, appVersion()) > 0;
    if (!available) {
        if (m_updateAvailable) {
            m_updateAvailable = false;
            m_updateVersion.clear();
            m_updateInstallerUrl.clear();
            m_updateSha256.clear();
            m_updateChangelog.clear();
            emit updateAvailableChanged();
        }
        if (manual)
            emit updateUpToDate();
        return;
    }

    m_updateVersion = version;
    m_updateInstallerUrl = map.value(QStringLiteral("installerUrl")).toString().trimmed();
    m_updateSha256 = map.value(QStringLiteral("sha256")).toString().trimmed();
    m_updateAvailable = true;
    emit updateAvailableChanged();

    const bool shouldShowPassiveUi = m_settings->autoCheckUpdates() || manual;
    if (shouldShowPassiveUi) {
        m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
        emit updateStatusTextChanged();
    } else if (!m_updateStatusText.isEmpty()) {
        m_updateStatusText.clear();
        emit updateStatusTextChanged();
    }

#if defined(Q_OS_WIN)
    if (manual || (m_settings->autoCheckUpdates() && m_settings->skippedUpdateVersion() != m_updateVersion))
        emit updateDialogRequested();
#else
    Q_UNUSED(manual)
#endif
}

void AppController::checkForUpdates(bool manual) {
    if (m_checkingForUpdates)
        return;

    m_updateCheckManual = manual;
    m_updateCheckStartedAt = QDateTime::currentDateTime();
    m_updateStatusText = QStringLiteral("📡 Checking for updates");
    emit updateStatusTextChanged();
    setCheckingForUpdates(true);

    QNetworkRequest request{QUrl(AppController::updateMetadataUrl())};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar/%1").arg(appVersion()));
    QNetworkReply *reply = m_nam->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, manual]() {
        const QByteArray payload = reply->readAll();
        const QString networkError = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
        reply->deleteLater();

        if (!networkError.isEmpty()) {
            finishUpdateCheckUi([this, networkError, manual]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
                if (manual)
                    emit updateError(QStringLiteral("Could not check for updates: %1").arg(networkError));
            });
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(payload);
        if (!doc.isObject()) {
            finishUpdateCheckUi([this, manual]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
                if (manual)
                    emit updateError(QStringLiteral("Update metadata is not valid JSON."));
            });
            return;
        }

        QVariantMap metadata = doc.object().toVariantMap();
        const QString version = metadata.value(QStringLiteral("version")).toString().trimmed();
        const bool available = !version.isEmpty() && compareVersionStrings(version, appVersion()) > 0;
        if (!available) {
            finishUpdateCheckUi([this, manual]() {
                m_updateAvailable = false;
                m_updateVersion.clear();
                m_updateInstallerUrl.clear();
                m_updateSha256.clear();
                m_updateChangelog.clear();
                emit updateAvailableChanged();
                m_updateStatusText.clear();
                emit updateStatusTextChanged();
                if (manual)
                    emit updateUpToDate();
            });
            return;
        }

        QNetworkRequest changelogRequest{QUrl(AppController::updateChangelogUrl())};
        changelogRequest.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar/%1").arg(appVersion()));
        QNetworkReply *changelogReply = m_nam->get(changelogRequest);
        connect(changelogReply, &QNetworkReply::finished, this, [this, changelogReply, manual, metadata]() mutable {
            const QString changelogText = changelogReply->error() == QNetworkReply::NoError
                ? QString::fromUtf8(changelogReply->readAll())
                : QString();
            changelogReply->deleteLater();
            metadata[QStringLiteral("changelog")] = changelogText;
            m_updateChangelog = metadata.value(QStringLiteral("changelog")).toString();
            applyUpdateMetadata(metadata, manual);
            finishUpdateCheckUi([this]() {
                if (!m_settings->autoCheckUpdates())
                    m_updateStatusText.clear();
                else if (m_updateAvailable)
                    m_updateStatusText = QStringLiteral("🎊 Update available! (%1)").arg(m_updateVersion);
                else
                    m_updateStatusText.clear();
                emit updateStatusTextChanged();
            });
        });
    });
}

void AppController::dismissAvailableUpdate() {
    if (!m_updateVersion.isEmpty())
        m_settings->setSkippedUpdateVersion(m_updateVersion);
}

bool AppController::startUpdateInstall() {
#if !defined(Q_OS_WIN)
    return false;
#else
    if (!m_updateAvailable || m_updateInstallerUrl.trimmed().isEmpty())
        return false;

    const QString tempDir = m_settings->temporaryDirectory().trimmed().isEmpty()
        ? (QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Stellar"))
        : m_settings->temporaryDirectory();
    QDir().mkpath(tempDir);

    const QString filename = QFileInfo(QUrl(m_updateInstallerUrl).path()).fileName().isEmpty()
        ? QStringLiteral("StellarSetup-%1.exe").arg(m_updateVersion)
        : QFileInfo(QUrl(m_updateInstallerUrl).path()).fileName();

    DownloadItem *item = createDownloadItem(
        m_updateInstallerUrl,
        tempDir,
        QStringLiteral("Other"),
        QStringLiteral("Stellar update installer"),
        true,
        QString(),
        QString(),
        QString(),
        QString(),
        QString(),
        filename,
        QString(),
        false);
    if (!item)
        return false;

    m_pendingUpdateDownloadId = item->id();
    m_pendingUpdateInstallerPath = tempDir + QStringLiteral("/") + filename;
    m_pendingUpdateSha256 = m_updateSha256;
    return true;
#endif
}


QString AppController::appVersion() const { return QStringLiteral(STELLAR_VERSION); }
QString AppController::buildTime()   const { return QStringLiteral(STELLAR_BUILD_TIME); }
QString AppController::buildTimeFormatted() const {
    // Convert UTC build time to Eastern time with natural language format (12-hour)
    // STELLAR_BUILD_TIME format: "2026-04-09 02:28 UTC"
    const QString buildStr = QStringLiteral(STELLAR_BUILD_TIME);
    QDateTime utcTime = QDateTime::fromString(buildStr.left(16), QStringLiteral("yyyy-MM-dd HH:mm"));
    if (!utcTime.isValid()) return buildStr;
    utcTime.setTimeSpec(Qt::UTC);

    // Convert to Eastern Time (ET = UTC - 5, EDT = UTC - 4)
    // For simplicity, assume daylight saving time based on month
    const int month = utcTime.date().month();
    const int offset = (month >= 3 && month <= 10) ? -4 : -5; // EDT or EST
    const QDateTime etTime = utcTime.addSecs(offset * 3600);

    // Format as natural language: "April 8, 2026 5:18 PM Eastern Daylight Time"
    const QString monthName = QLocale().standaloneMonthName(etTime.date().month(), QLocale::LongFormat);
    const QString ampm = etTime.time().hour() < 12 ? QStringLiteral("AM") : QStringLiteral("PM");
    const int hour12 = etTime.time().hour() % 12;
    const int finalHour = (hour12 == 0) ? 12 : hour12;
    const QString tzName = (offset == -4) ? QStringLiteral("EDT") : QStringLiteral("EST");

    return QString(QStringLiteral("%1 %2, %3 %4:%5 %6 %7"))
        .arg(monthName)
        .arg(etTime.date().day())
        .arg(etTime.date().year())
        .arg(finalHour)
        .arg(etTime.time().minute(), 2, 10, QLatin1Char('0'))
        .arg(ampm)
        .arg(tzName);
}
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

int AppController::recentErrorDownloads() const {
    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-300);
    int count = 0;
    for (auto it = m_recentErrorDownloads.constBegin(); it != m_recentErrorDownloads.constEnd(); ++it) {
        if (it.value().isValid() && it.value() >= cutoff)
            ++count;
    }
    return count;
}

QStringList AppController::queueIds() const {
    QStringList ids;
    if (!m_queueModel) return ids;
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q && q->id() != QStringLiteral("download-limits"))
            ids.append(q->id());
    }
    return ids;
}

QStringList AppController::queueNames() const {
    QStringList names;
    if (!m_queueModel) return names;
    for (int i = 0; i < m_queueModel->rowCount(); ++i) {
        Queue *q = m_queueModel->queueAt(i);
        if (q && q->id() != QStringLiteral("download-limits"))
            names.append(q->name());
    }
    return names;
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
    connect(item, &DownloadItem::doneBytesChanged, this, [this, item]() {
        if (item && !item->queueId().isEmpty())
            enforceQueueDownloadLimits(item->queueId());
    });
    connect(item, &DownloadItem::queueIdChanged, this, [this, item]() {
        if (item)
            enforceQueueDownloadLimits(item->queueId());
    });
    connect(item, &DownloadItem::statusChanged, this, [this, item, id]() {
        if (item && item->statusEnum() != DownloadItem::Status::Error) {
            if (m_recentErrorDownloads.remove(id) > 0)
                emit recentErrorDownloadsChanged();
        }
    });
}

void AppController::pruneRecentErrorDownloads() {
    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-300);
    bool changed = false;
    for (auto it = m_recentErrorDownloads.begin(); it != m_recentErrorDownloads.end(); ) {
        if (!it.value().isValid() || it.value() < cutoff) {
            it = m_recentErrorDownloads.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed)
        emit recentErrorDownloadsChanged();
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

void AppController::cleanupTemporaryDirectory()
{
    const QString tempDirPath = m_settings ? m_settings->temporaryDirectory().trimmed() : QString();
    if (tempDirPath.isEmpty())
        return;

    QDir tempDir(tempDirPath);
    if (!tempDir.exists())
        return;

    QSet<QString> activePaths;
    for (DownloadItem *item : m_queue->items()) {
        if (!item)
            continue;
        const QString baseName = tempDir.absoluteFilePath(item->filename());
        activePaths.insert(baseName + QStringLiteral(".stellar-meta"));
        for (int i = 0; i < 32; ++i)
            activePaths.insert(baseName + QStringLiteral(".stellar-part-") + QString::number(i));
        activePaths.insert(tempDir.absoluteFilePath(item->filename()));
    }

    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-2);
    const QFileInfoList entries = tempDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QString filePath = entry.absoluteFilePath();
        const QString fileName = entry.fileName();
        const bool isStellarTemp = fileName.contains(QStringLiteral(".stellar-part-"))
            || fileName.endsWith(QStringLiteral(".stellar-meta"))
            || fileName.endsWith(QStringLiteral(".stellar-pending"));
        if (!isStellarTemp)
            continue;
        if (activePaths.contains(filePath))
            continue;
        if (entry.lastModified() > cutoff)
            continue;
        QFile::remove(filePath);
    }
}

bool AppController::canStartDownloadItem(DownloadItem *item) const
{
    if (!item)
        return false;

    const QString queueId = item->queueId();
    if (queueId.isEmpty())
        return true;

    Queue *queue = m_queueModel ? m_queueModel->queueById(queueId) : nullptr;
    if (!queue || queue->id() == QStringLiteral("download-limits"))
        return true;

    int activeForQueue = 0;
    for (DownloadItem *candidate : m_queue->items()) {
        if (!candidate || candidate->queueId() != queueId)
            continue;
        if (candidate->statusEnum() == DownloadItem::Status::Downloading
            || candidate->statusEnum() == DownloadItem::Status::Assembling) {
            ++activeForQueue;
        }
    }
    if (queue->maxConcurrentDownloads() > 0 && activeForQueue >= queue->maxConcurrentDownloads())
        return false;

    if (queue->hasDownloadLimits()) {
        const qint64 limitBytes = static_cast<qint64>(queue->downloadLimitMBytes()) * 1024 * 1024;
        if (limitBytes > 0 && queueTransferredBytesInWindow(queueId, queue->downloadLimitHours()) >= limitBytes)
            return false;
    }

    return true;
}

void AppController::pruneQueueTransferHistory(const QString &queueId, int hours) const
{
    if (queueId.isEmpty() || hours <= 0 || !m_queueTransferHistory.contains(queueId))
        return;

    const QDateTime cutoff = QDateTime::currentDateTime().addSecs(-hours * 3600);
    auto &entries = m_queueTransferHistory[queueId];
    while (!entries.isEmpty() && entries.front().first < cutoff)
        entries.removeFirst();
}

qint64 AppController::queueTransferredBytesInWindow(const QString &queueId, int hours) const
{
    if (queueId.isEmpty() || hours <= 0)
        return 0;

    pruneQueueTransferHistory(queueId, hours);

    qint64 total = 0;
    const auto history = m_queueTransferHistory.value(queueId);
    for (const auto &entry : history)
        total += entry.second;

    for (DownloadItem *item : m_queue->items()) {
        if (!item || item->queueId() != queueId)
            continue;
        if (item->statusEnum() == DownloadItem::Status::Completed
            || item->statusEnum() == DownloadItem::Status::Error)
            continue;
        total += item->doneBytes();
    }

    return total;
}

void AppController::recordQueueTransferSample(const QString &queueId, qint64 bytes)
{
    if (queueId.isEmpty() || bytes <= 0)
        return;

    m_queueTransferHistory[queueId].append(qMakePair(QDateTime::currentDateTime(), bytes));
}

void AppController::enforceQueueDownloadLimits(const QString &queueId)
{
    if (queueId.isEmpty() || !m_queueModel)
        return;

    Queue *queue = m_queueModel->queueById(queueId);
    if (!queue || !queue->hasDownloadLimits() || queue->downloadLimitHours() <= 0) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    const qint64 limitBytes = static_cast<qint64>(queue->downloadLimitMBytes()) * 1024 * 1024;
    if (limitBytes <= 0) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    const qint64 usedBytes = queueTransferredBytesInWindow(queueId, queue->downloadLimitHours());
    if (usedBytes < limitBytes) {
        m_queueLimitNotifications.remove(queueId);
        return;
    }

    stopQueue(queueId);

    if (!m_queueLimitNotifications.contains(queueId)) {
        m_queueLimitNotifications.insert(queueId);
        const QString message = QStringLiteral("%1 reached its %2 MB / %3 hour limit.")
            .arg(queue->name())
            .arg(queue->downloadLimitMBytes())
            .arg(queue->downloadLimitHours());
        if (queue->warnBeforeStopping() && m_tray)
            m_tray->showNotification(QStringLiteral("Queue Limit Reached"), message);
        else
            qDebug() << "[QueueLimit]" << message;
    }
}

QVariantMap AppController::grabberProjectData(const QString &projectId) const
{
    return m_grabberProjectModel ? m_grabberProjectModel->projectDataById(projectId) : QVariantMap{};
}

bool AppController::isGrabberProjectId(const QString &projectId) const
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return false;
    return !m_grabberProjectModel->projectDataById(projectId).isEmpty();
}

QString AppController::saveGrabberProject(const QVariantMap &projectMap)
{
    if (!m_grabberProjectModel)
        return {};

    QVariantMap copy = projectMap;
    if (copy.value(QStringLiteral("statusText")).toString().isEmpty())
        copy[QStringLiteral("statusText")] = QStringLiteral("Ready");
    return m_grabberProjectModel->upsertProject(copy);
}

void AppController::deleteGrabberProject(const QString &projectId)
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return;

    m_grabberProjectModel->removeProject(projectId);

    // Reassign existing downloads to "all" semantics once their project bucket
    // disappears, so filtering never points at a dangling project id.
    for (DownloadItem *item : m_downloadModel->allItems()) {
        if (item && item->category() == projectId) {
            item->setCategory(QStringLiteral("all"));
            scheduleSave(item->id());
        }
    }
}

void AppController::runGrabber(const QVariantMap &projectMap)
{
    if (!m_grabberCrawler || !m_grabberProjectModel)
        return;

    QVariantMap copy = projectMap;
    const QString projectId = saveGrabberProject(copy);
    m_activeGrabberProjectId = projectId;
    m_grabberPagesProcessed = 0;
    m_grabberAdvancedPagesProcessed = 0;
    m_grabberMatchedFiles = 0;
    m_grabberBusy = true;
    emit grabberBusyChanged();
    m_grabberStatusText = QStringLiteral("Starting crawl...");
    emit grabberStatusTextChanged();
    m_grabberResultModel->setResults({});
    copy[QStringLiteral("id")] = projectId;
    m_grabberCrawler->start(copy);
}

void AppController::cancelGrabber()
{
    if (!m_grabberCrawler || !m_grabberBusy)
        return;

    m_grabberCrawler->cancel();
    m_grabberBusy = false;
    emit grabberBusyChanged();
    m_grabberStatusText = QStringLiteral("Grabber cancelled");
    emit grabberStatusTextChanged();
}

void AppController::setGrabberResultChecked(int row, bool checked)
{
    if (m_grabberResultModel) {
        m_grabberResultModel->setChecked(row, checked);
        scheduleGrabberResultsPersist();
    }
}

void AppController::setAllGrabberResultsChecked(bool checked)
{
    if (m_grabberResultModel) {
        m_grabberResultModel->setAllChecked(checked);
        scheduleGrabberResultsPersist();
    }
}

int AppController::checkedGrabberResultCount() const
{
    return m_grabberResultModel ? m_grabberResultModel->checkedCount() : 0;
}

void AppController::sortGrabberResults(const QString &column, bool ascending)
{
    if (!m_grabberResultModel)
        return;

    m_grabberResultModel->sortBy(column,
                                 ascending ? Qt::AscendingOrder : Qt::DescendingOrder);
    scheduleGrabberResultsPersist();
}

void AppController::scheduleGrabberResultsPersist()
{
    if (!m_grabberPersistTimer)
        return;
    m_grabberPersistTimer->start();
}

void AppController::persistActiveGrabberResults()
{
    if (!m_grabberProjectModel || !m_grabberResultModel || m_activeGrabberProjectId.isEmpty())
        return;

    QVariantMap project = m_grabberProjectModel->projectDataById(m_activeGrabberProjectId);
    if (project.isEmpty())
        return;

    // Keep the latest results and check-state with the project so scheduled
    // actions and reopened Grabber sessions can reuse the same selection.
    project[QStringLiteral("lastResults")] = m_grabberResultModel->allResults();
    project[QStringLiteral("lastResultCount")] = m_grabberResultModel->rowCount();
    m_grabberProjectModel->upsertProject(project);
}

void AppController::loadGrabberProjectResults(const QString &projectId)
{
    if (!m_grabberResultModel || !m_grabberProjectModel || projectId.isEmpty())
        return;

    const QVariantMap project = m_grabberProjectModel->projectDataById(projectId);
    const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
    m_activeGrabberProjectId = projectId;
    m_grabberResultModel->setResults(savedResults);
    m_grabberMatchedFiles = savedResults.size();
}

QString AppController::resolveGrabberSaveDirectory(const QVariantMap &project,
                                                   const QUrl &url,
                                                   const QString &filename,
                                                   QString *resolvedCategory) const
{
    // Grabber projects can choose a save destination strategy independently of
    // the category bucket used for sidebar grouping.
    const QString saveMode = project.value(QStringLiteral("saveMode"), QStringLiteral("directory")).toString();
    QString categoryId = project.value(QStringLiteral("projectCategoryId")).toString();
    QString targetDir = project.value(QStringLiteral("savePath")).toString().trimmed();

    if (saveMode == QStringLiteral("byCategory")) {
        categoryId = m_categoryModel->categoryForUrl(url, filename);
        targetDir = m_categoryModel->savePathForCategory(categoryId);
    } else if (saveMode == QStringLiteral("selectedCategory")) {
        categoryId = project.value(QStringLiteral("selectedCategoryId")).toString();
        if (categoryId.isEmpty())
            categoryId = QStringLiteral("all");
        targetDir = m_categoryModel->savePathForCategory(categoryId);
    }

    if (targetDir.isEmpty())
        targetDir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);

    if (project.value(QStringLiteral("useRelativeSubfolders")).toBool()) {
        QString relativePath = QFileInfo(url.path()).path();
        relativePath.remove(QRegularExpression(QStringLiteral("^/+")));
        if (!relativePath.isEmpty() && relativePath != QStringLiteral(".")) {
            targetDir = QDir(targetDir).filePath(relativePath);
            QDir().mkpath(targetDir);
        }
    }

    if (resolvedCategory)
        *resolvedCategory = categoryId;
    return targetDir;
}

void AppController::downloadGrabberResults(const QString &projectId, bool startNow, const QString &queueId)
{
    if (!m_grabberResultModel)
        return;

    const QVariantMap project = grabberProjectData(projectId);
    QVariantList checked = m_grabberResultModel->checkedResults();
    if (checked.isEmpty()) {
        const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
        for (const QVariant &value : savedResults) {
            const QVariantMap result = value.toMap();
            if (result.value(QStringLiteral("checked"), true).toBool())
                checked.append(result);
        }
    }
    for (const QVariant &value : checked) {
        const QVariantMap result = value.toMap();
        const QString urlString = result.value(QStringLiteral("url")).toString();
        const QString filename = result.value(QStringLiteral("filename")).toString();
        if (urlString.isEmpty())
            continue;

        const QUrl url = QUrl::fromUserInput(urlString);
        QString ignoredResolvedCategory;
        const QString saveDir = resolveGrabberSaveDirectory(project, url, filename, &ignoredResolvedCategory);
        QString finalFilename = filename;
        if (!project.value(QStringLiteral("overwriteExistingFiles")).toBool()) {
            const QFileInfo info(filename);
            const QString base = info.completeBaseName();
            const QString ext = info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix();
            int suffix = 1;
            while (QFile::exists(QDir(saveDir).filePath(finalFilename))) {
                finalFilename = QStringLiteral("%1_%2%3").arg(base).arg(suffix).arg(ext);
                ++suffix;
            }
        }
        // Grabber projects intentionally keep their own category bucket so the
        // sidebar can show "project folders" independent of normal file-type categories.
        addUrl(urlString, saveDir, projectId, project.value(QStringLiteral("comment")).toString(),
               startNow, {}, {}, {}, {}, {}, finalFilename, queueId);
    }

    if (!projectId.isEmpty() && m_grabberProjectModel) {
        m_grabberProjectModel->updateProjectRunState(
            projectId,
            QStringLiteral("Added %1 downloads").arg(checked.size()),
            m_grabberResultModel->rowCount());
    }
}

void AppController::stopGrabberResultDownloads(const QString &projectId)
{
    if (!m_grabberResultModel)
        return;

    QVariantList checked = m_grabberResultModel->checkedResults();
    if (checked.isEmpty()) {
        const QVariantMap project = grabberProjectData(projectId);
        const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
        for (const QVariant &value : savedResults) {
            const QVariantMap result = value.toMap();
            if (result.value(QStringLiteral("checked"), true).toBool())
                checked.append(result);
        }
    }
    for (const QVariant &value : checked) {
        const QString urlString = value.toMap().value(QStringLiteral("url")).toString();
        if (urlString.isEmpty())
            continue;
        DownloadItem *item = m_downloadModel->itemByUrl(QUrl::fromUserInput(urlString));
        if (item && item->category() == projectId)
            pauseDownload(item->id());
    }
}

QVariantMap AppController::grabberStatistics(const QString &projectId) const
{
    const QVariantMap project = grabberProjectData(projectId);
    const QVariantList savedResults = project.value(QStringLiteral("lastResults")).toList();
    int downloaded = 0;
    int totalForProject = 0;
    for (DownloadItem *item : m_downloadModel->allItems()) {
        if (!item || item->category() != projectId)
            continue;
        ++totalForProject;
        if (item->status() == QStringLiteral("Completed"))
            ++downloaded;
    }

    return QVariantMap{
        { QStringLiteral("status"), m_grabberBusy ? m_grabberStatusText : QStringLiteral("Idle") },
        { QStringLiteral("webPagesProcessed"), m_grabberPagesProcessed },
        { QStringLiteral("advancedPagesProcessed"), m_grabberAdvancedPagesProcessed },
        { QStringLiteral("filesTotal"), savedResults.size() },
        { QStringLiteral("filesExplored"), savedResults.size() },
        { QStringLiteral("filesMatched"), m_grabberMatchedFiles },
        { QStringLiteral("filesDownloaded"), downloaded },
        { QStringLiteral("projectDownloads"), totalForProject }
    };
}

void AppController::saveGrabberProjectSchedule(const QString &projectId, const QVariantMap &scheduleMap)
{
    if (!m_grabberProjectModel || projectId.isEmpty())
        return;

    QVariantMap project = m_grabberProjectModel->projectDataById(projectId);
    if (project.isEmpty())
        return;
    project[QStringLiteral("schedule")] = scheduleMap;
    m_grabberProjectModel->upsertProject(project);
}

QString AppController::readTextResource(const QString &path) const
{
    QString resolvedPath = path;
    if (resolvedPath.startsWith(QStringLiteral("qrc:/")))
        resolvedPath = QStringLiteral(":") + resolvedPath.mid(4);

    QFile file(resolvedPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (resolvedPath == QStringLiteral(":/qt/qml/com/stellar/app/tips.txt")
            || resolvedPath == QStringLiteral(":/tips.txt")) {
            const QString localPath = QCoreApplication::applicationDirPath()
                + QDir::separator()
                + QStringLiteral("tips.txt");
            file.setFileName(localPath);
        }
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    return QString::fromUtf8(file.readAll());
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
    // Remove all downloads from this queue so they're unqueued
    for (auto *item : m_downloadModel->allItems()) {
        if (item && item->queueId() == queueId) {
            item->setQueueId("");
        }
    }
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

    // Mark all items in this queue as "Queued" so scheduleNext will start them
    // respecting the queue's maxConcurrentDownloads limit as capacity becomes available
    int queuedCount = 0;
    for (DownloadItem *item : m_queue->items()) {
        if (item->queueId() == queueId && (item->status() == QStringLiteral("Paused") || item->status() == QStringLiteral("Queued"))) {
            if (item->status() != QStringLiteral("Queued")) {
                item->setStatus(DownloadItem::Status::Queued);
            }
            ++queuedCount;
        }
    }

    // Now trigger scheduleNext to start up to maxConcurrent downloads
    m_queue->scheduleNext();

    qDebug() << "Starting queue" << queueId << q->name() << "- queued" << queuedCount << "downloads";
}

void AppController::setTrayTooltip(const QString &tip) {
    if (m_tray) m_tray->setToolTip(tip);
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

bool AppController::shutdownComputer() const
{
#if defined(Q_OS_WIN)
    return QProcess::startDetached(QStringLiteral("shutdown"),
                                   { QStringLiteral("/s"), QStringLiteral("/t"), QStringLiteral("0") });
#elif defined(Q_OS_LINUX)
    if (QProcess::startDetached(QStringLiteral("systemctl"),
                                { QStringLiteral("poweroff") })) {
        return true;
    }
    return QProcess::startDetached(QStringLiteral("shutdown"),
                                   { QStringLiteral("-h"), QStringLiteral("now") });
#else
    return false;
#endif
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

    if (m_grabberProjectModel && !m_grabberBusy) {
        const QDateTime now = QDateTime::currentDateTime();
        for (const GrabberProject &project : m_grabberProjectModel->projects()) {
            const QVariantMap projectMap = project.config.toVariantMap();
            const QVariantMap schedule = projectMap.value(QStringLiteral("schedule")).toMap();
            if (!schedule.value(QStringLiteral("enabled")).toBool())
                continue;

            const QString mode = schedule.value(QStringLiteral("mode"), QStringLiteral("once")).toString();
            const QTime startTime = QTime::fromString(schedule.value(QStringLiteral("startTime")).toString(), QStringLiteral("hh:mm AP"));
            if (!startTime.isValid())
                continue;

            const QDateTime lastRun = QDateTime::fromString(projectMap.value(QStringLiteral("lastScheduledRunAt")).toString(), Qt::ISODate);
            bool shouldRun = false;

            if (mode == QStringLiteral("periodic")) {
                const int everyHours = schedule.value(QStringLiteral("everyHours"), 2).toInt();
                const int everyMinutes = schedule.value(QStringLiteral("everyMinutes"), 0).toInt();
                const int intervalSecs = everyHours * 3600 + everyMinutes * 60;
                if (intervalSecs > 0) {
                    const QDateTime effectiveLastRun = lastRun.isValid() ? lastRun : now.addSecs(-intervalSecs - 60);
                    shouldRun = effectiveLastRun.secsTo(now) >= intervalSecs;
                }
            } else {
                QDateTime scheduled = QDateTime(now.date(), startTime);
                if (scheduled > now)
                    continue;

                if (mode == QStringLiteral("daily")) {
                    const QStringList days = schedule.value(QStringLiteral("days")).toStringList();
                    const QString today = now.toString(QStringLiteral("dddd"));
                    shouldRun = days.isEmpty() || days.contains(today);
                    if (shouldRun && lastRun.isValid() && lastRun.date() == now.date())
                        shouldRun = false;
                } else {
                    const QDate targetDate = QDate::fromString(schedule.value(QStringLiteral("date")).toString(), Qt::ISODate);
                    shouldRun = targetDate.isValid() && targetDate == now.date() && (!lastRun.isValid());
                }
            }

            if (!shouldRun)
            {
                if (schedule.value(QStringLiteral("stopEnabled")).toBool()) {
                    const QTime stopTime = QTime::fromString(schedule.value(QStringLiteral("stopTime")).toString(), QStringLiteral("hh:mm AP"));
                    if (stopTime.isValid()) {
                        const int nowMins = now.time().hour() * 60 + now.time().minute();
                        const int stopMins = stopTime.hour() * 60 + stopTime.minute();
                        if (qAbs(nowMins - stopMins) <= 2)
                            stopGrabberResultDownloads(project.id);
                    }
                }
                continue;
            }

            QVariantMap updatedProject = projectMap;
            updatedProject[QStringLiteral("lastScheduledRunAt")] = now.toString(Qt::ISODate);
            m_grabberProjectModel->upsertProject(updatedProject);
            const QString scheduledAction = schedule.value(QStringLiteral("action"), QStringLiteral("exploreOnly")).toString();
            if (scheduledAction == QStringLiteral("downloadChecked")) {
                loadGrabberProjectResults(project.id);
                downloadGrabberResults(project.id, true);
            } else {
                if (scheduledAction == QStringLiteral("exploreAndDownload"))
                    updatedProject[QStringLiteral("startDownloadingImmediately")] = true;
                runGrabber(updatedProject);
            }
            break;
        }
    }

    int currentMinutes = calculateMinutesUntilNextQueue();
    if (currentMinutes != prevMinutes) {
        emit minutesUntilNextQueueChanged();
    }
}
