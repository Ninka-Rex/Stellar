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
#include <QObject>
#include <QNetworkAccessManager>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>
#include <QSet>
#include <QMap>
#include "DownloadQueue.h"
#include "DownloadTableModel.h"
#include "CategoryModel.h"
#include "NativeMessagingHost.h"
#include "AppSettings.h"
#include "SystemTrayIcon.h"
#include "DownloadDatabase.h"
#include "QueueDatabase.h"
#include "QueueModel.h"

class AppController : public QObject {
    Q_OBJECT
    Q_PROPERTY(DownloadTableModel *downloadModel READ downloadModel CONSTANT)
    Q_PROPERTY(CategoryModel      *categoryModel READ categoryModel CONSTANT)
    Q_PROPERTY(class QueueModel   *queueModel    READ queueModel    CONSTANT)
    Q_PROPERTY(AppSettings        *settings      READ settings      CONSTANT)
    Q_PROPERTY(int     activeDownloads    READ activeDownloads    NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QString selectedCategory  READ selectedCategory   WRITE setSelectedCategory NOTIFY selectedCategoryChanged)
    Q_PROPERTY(QString appVersion   READ appVersion   CONSTANT)
    Q_PROPERTY(QString buildTime    READ buildTime    CONSTANT)
    Q_PROPERTY(QString qtVersion    READ qtVersion    CONSTANT)
    Q_PROPERTY(int minutesUntilNextQueue READ minutesUntilNextQueue NOTIFY minutesUntilNextQueueChanged)

public:
    explicit AppController(QObject *parent = nullptr);

    DownloadTableModel *downloadModel() const { return m_downloadModel; }
    CategoryModel      *categoryModel() const { return m_categoryModel; }
    class QueueModel   *queueModel()    const { return m_queueModel; }
    AppSettings        *settings()      const { return m_settings; }
    int  activeDownloads() const;
    QString selectedCategory() const { return m_selectedCategory; }
    void setSelectedCategory(const QString &v);
    QString appVersion() const;
    QString buildTime() const;
    QString qtVersion() const;
    int minutesUntilNextQueue() const;

    Q_INVOKABLE void addUrl(const QString &url, const QString &savePath = {},
                            const QString &category = {}, const QString &description = {},
                            bool startNow = true, const QString &cookies = {},
                            const QString &referrer = {}, const QString &parentUrl = {},
                            const QString &username = {}, const QString &password = {});
    Q_INVOKABLE void deleteAllCompleted(int mode = 0);
    Q_INVOKABLE void pauseAllDownloads();
    Q_INVOKABLE void sortDownloads(const QString &column, bool ascending);
    Q_INVOKABLE void pauseDownload(const QString &id);
    Q_INVOKABLE void resumeDownload(const QString &id);
    // mode: 0 = list only, 1 = delete file permanently, 2 = move to trash
    Q_INVOKABLE void deleteDownload(const QString &id, int mode = 0);
    Q_INVOKABLE void openFile(const QString &id);
    Q_INVOKABLE void openFolder(const QString &id);
    Q_INVOKABLE void openFolderSelectFile(const QString &id);
    Q_INVOKABLE void moveFileToDesktop(const QString &id);
    Q_INVOKABLE void copyDownloadFilename(const QString &id);
    Q_INVOKABLE QString clipboardUrl() const;
    Q_INVOKABLE void setDownloadCategory(const QString &downloadId, const QString &categoryId);
    Q_INVOKABLE void setDownloadQueue(const QString &downloadId, const QString &queueId);
    Q_INVOKABLE void moveUpInQueue(const QString &downloadId);
    Q_INVOKABLE void moveDownInQueue(const QString &downloadId);
    Q_INVOKABLE QObject *findDuplicateUrl(const QString &url) const;
    Q_INVOKABLE QString  generateNumberedFilename(const QString &filename) const;
    Q_INVOKABLE void     copyToClipboard(const QString &text) const;
    Q_INVOKABLE void     openExtensionFolder() const;
    Q_INVOKABLE void     addExcludedAddress(const QString &pattern);
    Q_INVOKABLE void     notifyInterceptRejected(const QString &url);
    Q_INVOKABLE void     setDownloadSpeedLimit(const QString &downloadId, int kbps);
    Q_INVOKABLE void     setDownloadUsername(const QString &downloadId, const QString &username);
    Q_INVOKABLE void     setDownloadPassword(const QString &downloadId, const QString &password);
    Q_INVOKABLE bool     moveDownloadFile(const QString &downloadId, const QString &newFilePath);
    Q_INVOKABLE void     enableSpeedLimiter();
    Q_INVOKABLE void     disableSpeedLimiter();
    // Cookie storage for browser-intercepted downloads.
    // Called by the IPC handler before emitting interceptedDownloadRequested.
    // QML calls takePendingCookies(url) when actually starting the download.
    Q_INVOKABLE void    setPendingCookies(const QString &url, const QString &cookies);
    Q_INVOKABLE QString takePendingCookies(const QString &url);
    Q_INVOKABLE QString takePendingReferrer(const QString &url);
    Q_INVOKABLE QString takePendingPageUrl(const QString &url);
    // Returns empty string on success, or an error message on failure.
    Q_INVOKABLE QString  registerNativeHost() const;
    // Returns the absolute path where the manifest was/would be written.
    Q_INVOKABLE QString  nativeHostManifestPath() const;
    // Returns a multi-line diagnostic string for troubleshooting.
    Q_INVOKABLE QString  nativeHostDiagnostics() const;

    // Queue management
    Q_INVOKABLE void createQueue(const QString &name);
    Q_INVOKABLE void deleteQueue(const QString &queueId);
    Q_INVOKABLE void saveQueues();
    Q_INVOKABLE void startQueue(const QString &queueId);
    Q_INVOKABLE void stopQueue(const QString &queueId);

signals:
    void activeDownloadsChanged();
    void selectedCategoryChanged();
    void errorOccurred(const QString &message);
    void showWindowRequested();
    void downloadAdded(QObject *item);
    void downloadCompleted(QObject *item);
    void trayGithubRequested();
    void trayAboutRequested();
    void traySpeedLimiterRequested();
    void contextMenuRequested(int x, int y);
    void exceptionDialogRequested(const QString &url);
    void interceptedDownloadRequested(const QString &url, const QString &filename);
    void minutesUntilNextQueueChanged();

private:
    QString generateId() const;

    DownloadQueue          *m_queue{nullptr};
    DownloadTableModel     *m_downloadModel{nullptr};
    CategoryModel          *m_categoryModel{nullptr};
    NativeMessagingHost    *m_nativeHost{nullptr};
    QNetworkAccessManager  *m_nam{nullptr};
    AppSettings            *m_settings{nullptr};
    SystemTrayIcon         *m_tray{nullptr};
    DownloadDatabase       *m_db{nullptr};
    class QueueDatabase    *m_queueDb{nullptr};
    class QueueModel       *m_queueModel{nullptr};
    QTimer                 *m_saveTimer{nullptr};
    QLocalServer           *m_ipcServer{nullptr};  // receives downloads from native host subprocesses
    QSet<QString>           m_dirtyIds;   // items needing a DB write
    QMap<QString, int>      m_cancelCounts;        // URL → number of times cancelled
    QMap<QString, int>      m_interceptRejectCounts; // URL → number of times intercept dialog rejected
    bool                    m_restoring{false};
    QMap<QString, QString>  m_pendingCookies;   // url → cookies for browser-intercepted downloads
    QMap<QString, QString>  m_pendingReferrers; // url → referrer for browser-intercepted downloads
    QMap<QString, QString>  m_pendingPageUrls;  // url → parent page URL for browser-intercepted downloads
    QString                 m_selectedCategory{QStringLiteral("all")};

    void watchItem(DownloadItem *item);
    void scheduleSave(const QString &id);
    void flushDirty();
    void checkQueueSchedules();
    int calculateMinutesUntilNextQueue() const;

    QTimer                 *m_schedulerTimer{nullptr};
    QMap<QString, QDateTime> m_lastQueueRun;  // queueId → last run time
};
