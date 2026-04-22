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

#include <QGuiApplication>
#include <QTimer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QLocalSocket>
#include <QLocalServer>
#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <iostream>
#include <QProcess>
#include <QThread>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QStandardPaths>
#include <QLibraryInfo>
#include "AppController.h"
#include "FileIconImageProvider.h"
#include "FileDragDropHelper.h"
#include "FileIconImageProvider.h"
#include "StellarPaths.h"
#include "RssArticleModel.h"
#include "RssFeedModel.h"
#include "RssManager.h"
#include "TorrentSearchManager.h"
#include "TorrentSearchPluginModel.h"
#include "TorrentSearchResultModel.h"

#if defined(Q_OS_WIN)
#  include <windows.h>
#else
#  include <sys/stat.h>
#  include <unistd.h>
#endif

// ── Low-level stdin/stdout helpers ────────────────────────────────────────────
// QFile::open(stdin/stdout) relies on the CRT FILE* pointers which are
// uninitialised in a Windows GUI-subsystem app even when Firefox has set up
// the Win32 pipe handles.  Use the Win32 / POSIX APIs directly.

#if defined(Q_OS_WIN)

static bool nmRead(void *buf, quint32 n)
{
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    quint32 total = 0;
    while (total < n) {
        DWORD got = 0;
        if (!ReadFile(h, static_cast<char *>(buf) + total, n - total, &got, nullptr) || got == 0)
            return false;
        total += got;
    }
    return true;
}

static bool nmWrite(const char *buf, quint32 n)
{
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    quint32 total = 0;
    while (total < n) {
        DWORD wrote = 0;
        if (!WriteFile(h, buf + total, n - total, &wrote, nullptr) || wrote == 0)
            return false;
        total += wrote;
    }
    FlushFileBuffers(h);
    return true;
}

static bool stdinIsPipe()
{
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    return h && h != INVALID_HANDLE_VALUE && GetFileType(h) == FILE_TYPE_PIPE;
}

#else  // POSIX

static bool nmRead(void *buf, quint32 n)
{
    quint32 total = 0;
    while (total < n) {
        ssize_t r = ::read(STDIN_FILENO, static_cast<char *>(buf) + total, n - total);
        if (r <= 0) return false;
        total += static_cast<quint32>(r);
    }
    return true;
}

static bool nmWrite(const char *buf, quint32 n)
{
    quint32 total = 0;
    while (total < n) {
        ssize_t w = ::write(STDOUT_FILENO, buf + total, n - total);
        if (w <= 0) return false;
        total += static_cast<quint32>(w);
    }
    return true;
}

static bool stdinIsPipe()
{
    struct stat st = {};
    if (::fstat(STDIN_FILENO, &st) != 0)
        return false;
    return S_ISFIFO(st.st_mode) || S_ISSOCK(st.st_mode);
}

#endif  // Q_OS_WIN

static void writeNativeMsg(const QByteArray &json)
{
    quint32 len = static_cast<quint32>(json.size());
    nmWrite(reinterpret_cast<const char *>(&len), 4);
    nmWrite(json.constData(), len);
}

// Path to the "pending download" drop file.  The native messaging host writes
// the raw IPC JSON here before launching the GUI so the GUI can replay it even
// if the IPC retry window expires before the app is ready to accept connections.
static QString pendingDownloadFilePath()
{
    // Use the system temp directory so it survives across process invocations
    // and doesn't require any special permissions.
    return QDir::tempPath() + QStringLiteral("/stellar_pending_download.json");
}

// ── Native-messaging host mode ────────────────────────────────────────────────
// Firefox spawns Stellar.exe for each sendNativeMessage call with stdin/stdout
// piped.  We read one length-prefixed JSON message, respond, and exit.
// A minimal QCoreApplication is created only when we need QLocalSocket (i.e.
// for forwarding downloads to the running GUI).

static void nmLog(const QString &msg)
{
    Q_UNUSED(msg);
}

static int runNativeMessagingHost(int argc, char *argv[])
{
    nmLog(QStringLiteral("native host invoked"));

    // Step 1 — read message from stdin (no Qt needed here).
    quint32 msgLen = 0;
    if (!nmRead(&msgLen, 4) || msgLen == 0 || msgLen > 1024u * 1024u) {
        nmLog(QStringLiteral("failed to read length header (msgLen=%1)").arg(msgLen));
        return 1;
    }

    QByteArray payload(static_cast<int>(msgLen), '\0');
    if (!nmRead(payload.data(), msgLen)) {
        nmLog(QStringLiteral("failed to read payload"));
        return 1;
    }

    const QJsonObject req  = QJsonDocument::fromJson(payload).object();
    const QString     type = req.value(QStringLiteral("type")).toString();
    nmLog(QStringLiteral("received type=%1 payload=%2").arg(type, QString::fromUtf8(payload)));

    // Step 2 — handle ping with no dependencies.
    if (type == QStringLiteral("ping")) {
        const QByteArray resp = QJsonDocument(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("ready")}
        }).toJson(QJsonDocument::Compact);
        writeNativeMsg(resp);
        nmLog(QStringLiteral("ping replied: %1").arg(QString::fromUtf8(resp)));
        return 0;
    }

    // Step 3 — forward download/focus to the running GUI via local socket.
    // getSettings reads QSettings directly — no socket needed, always up-to-date.
    // QCoreApplication is required for QLocalSocket and QSettings.
    QCoreApplication coreApp(argc, argv);
    // Org/app names MUST match the GUI app — StellarPaths::root() derives the
    // settings directory from QStandardPaths::AppLocalDataLocation, which uses
    // these names. Without them, the native host reads a different INI file
    // (or none at all) and returns defaults instead of user-configured lists.
    QCoreApplication::setApplicationName(QStringLiteral("Stellar"));
    QCoreApplication::setOrganizationName(QStringLiteral("Stellar"));

    if (type == QStringLiteral("download") || type == QStringLiteral("focus")) {
        QLocalSocket sock;
        sock.connectToServer(QStringLiteral("StellarDownloadManager"));
        if (!sock.waitForConnected(500)) {
            const bool isDownload = (type == QStringLiteral("download"));
            // Main app isn't running. For downloads, persist the payload to the
            // drop file and let the GUI replay it on startup.
            //
            // IMPORTANT: do not "optimize" cold-start downloads back to socket
            // delivery here. On Windows, the native host can connect and write
            // before the GUI event loop is actually servicing IPC, so treating
            // that write as success and deleting the drop file causes the New
            // Download dialog to vanish on first launch after interception.
            nmLog(isDownload
                      ? QStringLiteral("Main app not running, writing pending download file and launching GUI...")
                      : QStringLiteral("Main app not running, launching GUI..."));
            if (isDownload) {
                QFile dropFile(pendingDownloadFilePath());
                if (dropFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
                    dropFile.write(payload);
            }

            QString program = QCoreApplication::applicationFilePath();
#if defined(Q_OS_WIN)
            // Firefox places native messaging hosts inside a Windows Job Object
            // with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.  A plain startDetached()
            // inherits that job, so the GUI process gets killed the moment
            // Firefox closes its job handle.  Break out of the job first.
            {
                QString cmdLine = QStringLiteral("\"%1\" --gui").arg(program);
                std::wstring cmdW = cmdLine.toStdWString();
                STARTUPINFOW si = {};
                si.cb = sizeof(si);
                PROCESS_INFORMATION pi = {};
                DWORD flags = CREATE_BREAKAWAY_FROM_JOB | CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS;
                if (!CreateProcessW(nullptr, cmdW.data(), nullptr, nullptr,
                                    FALSE, flags, nullptr, nullptr, &si, &pi)) {
                    // Job may not allow breakaway — fall back to plain launch.
                    nmLog(QStringLiteral("CreateProcess with BREAKAWAY failed (%1), falling back").arg(GetLastError()));
                    QProcess::startDetached(program, {QStringLiteral("--gui")});
                } else {
                    CloseHandle(pi.hProcess);
                    CloseHandle(pi.hThread);
                }
            }
#else
            QProcess::startDetached(program, {QStringLiteral("--gui")});
#endif
            if (isDownload) {
                nmLog(QStringLiteral("Cold-start download will be replayed from drop file on startup"));
            } else {
                // Focus-only requests don't need durable replay. Best-effort retry
                // is enough once the GUI has had a moment to finish starting.
                bool connected = false;
                for (int i = 0; i < 40; ++i) {
                    QThread::msleep(500);
                    sock.connectToServer(QStringLiteral("StellarDownloadManager"));
                    if (sock.waitForConnected(500)) {
                        connected = true;
                        break;
                    }
                }
                if (!connected) {
                    nmLog(QStringLiteral("Focus IPC retry window expired"));
                }
            }
        }

        if (sock.state() == QLocalSocket::ConnectedState) {
            sock.write(payload);
            sock.flush();
            sock.waitForBytesWritten(3000);
            nmLog(QStringLiteral("Successfully forwarded payload to main app via IPC"));
        }
        
        // Always ack so the extension Promise resolves cleanly.
        writeNativeMsg(QJsonDocument(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("ack")}
        }).toJson(QJsonDocument::Compact));
        return 0;
    }

    if (type == QStringLiteral("getSettings")) {
        // Read settings directly from the INI file — no need for the running app.
        // This means changes saved by the app are immediately visible to the extension.
        QSettings s(StellarPaths::settingsFile(), QSettings::IniFormat);

        auto toJsonArray = [&](const QString &key, const QStringList &defaultVal) -> QJsonArray {
            const QVariant v = s.value(key);
            QStringList list = v.isValid() ? v.toStringList() : defaultVal;
            // Legacy entries may have been stored as a single comma-joined QString
            // rather than a QStringList. Detect that and split on commas.
            if (list.size() == 1 && list.first().contains(QLatin1Char(','))) {
                const QStringList parts = list.first().split(QLatin1Char(','), Qt::SkipEmptyParts);
                list.clear();
                for (const QString &p : parts) {
                    const QString t = p.trimmed();
                    if (!t.isEmpty()) list << t;
                }
            }
            if (list.isEmpty()) list = defaultVal;
            QJsonArray arr;
            for (const QString &item : list) arr.append(item);
            return arr;
        };

        const QJsonObject resp = {
            {QStringLiteral("type"),               QStringLiteral("settings")},
            {QStringLiteral("monitoredExtensions"), toJsonArray(QStringLiteral("monitoredExtensions"), AppSettings::defaultMonitoredExtensions())},
            {QStringLiteral("excludedSites"),       toJsonArray(QStringLiteral("excludedSites"),       AppSettings::defaultExcludedSites())},
            {QStringLiteral("excludedAddresses"),   toJsonArray(QStringLiteral("excludedAddresses"),   AppSettings::defaultExcludedAddresses())}
        };
        const QByteArray respData = QJsonDocument(resp).toJson(QJsonDocument::Compact);
        nmLog(QStringLiteral("getSettings: returning %1 exts, %2 sites, %3 addrs")
            .arg(resp[QStringLiteral("monitoredExtensions")].toArray().size())
            .arg(resp[QStringLiteral("excludedSites")].toArray().size())
            .arg(resp[QStringLiteral("excludedAddresses")].toArray().size()));
        writeNativeMsg(respData);
        return 0;
    }

    // Unknown message type — ack so the extension Promise resolves cleanly.
    writeNativeMsg(QJsonDocument(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("ack")}
    }).toJson(QJsonDocument::Compact));
    return 0;
}

// ── GUI mode ──────────────────────────────────────────────────────────────────

int main(int argc, char *argv[])
{
    QString argsStr;
    for (int i = 0; i < argc; ++i) {
        argsStr += QString::fromUtf8(argv[i]) + " ";
    }
    nmLog(QStringLiteral("App started with args: ") + argsStr);

    bool forceGui = false;
    bool startMinimized = false;
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], "--gui") == 0)
            forceGui = true;
        else if (qstrcmp(argv[i], "--minimized") == 0)
            startMinimized = true;
    }
    
    nmLog(QStringLiteral("App startup. forceGui=") + (forceGui ? "true" : "false"));
    nmLog(QStringLiteral("Checking for existing instance..."));
    
    // Detect native-messaging mode before constructing QGuiApplication — it
    // would try to connect to a display that doesn't exist in a subprocess.
    if (!forceGui && stdinIsPipe()) {
        nmLog(QStringLiteral("stdinIsPipe=true, entering native host mode"));
        return runNativeMessagingHost(argc, argv);
    }

    nmLog(QStringLiteral("Constructing QGuiApplication..."));
    QGuiApplication app(argc, argv);
    nmLog(QStringLiteral("QGuiApplication constructed."));
    
    app.setApplicationName(QStringLiteral("Stellar"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("Stellar"));
    app.setWindowIcon(QIcon(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/icons/milky-way.png")));

    // Qt writes several caches under QStandardPaths::CacheLocation, which
    // defaults to %LOCALAPPDATA%\<Org>\<App>\cache\.  Redirect both the QML
    // bytecode cache and the RHI shader pipeline cache into our unified data
    // root so everything stays under %LOCALAPPDATA%\Stellar\cache\ with no
    // double-nesting.  Both env vars must be set before the QML engine and
    // QQuickWindow are constructed.
    const QByteArray cacheDir = StellarPaths::cacheDir().toUtf8();
    qputenv("QML_DISK_CACHE_PATH",        cacheDir); // QML bytecode cache
    qputenv("QSG_RHI_PIPELINE_CACHE_DIR", cacheDir); // RHI pipeline cache (Qt 6.5+)

    // One-time migration from the legacy data layout to the unified Stellar/
    // directory structure.  Must run before any component opens a database or
    // settings file so that all subsequent opens find data in the new location.
    StellarPaths::migrateIfNeeded();

    // Single-instance guard: try to reach an already-running instance first.
    // Only remove stale server entries when connect is explicitly refused.
    const QString kServerName = QStringLiteral("StellarDownloadManager");
    {
        nmLog(QStringLiteral("Connecting to existing instance socket..."));
        QLocalSocket sock;
        sock.connectToServer(kServerName);
        if (sock.waitForConnected(500)) {
            nmLog(QStringLiteral("Existing instance found, sending focus message..."));
            // Another instance is running — tell it to raise its window and exit.
            const QByteArray msg = QJsonDocument(
                QJsonObject{{QStringLiteral("type"), QStringLiteral("focus")}}
            ).toJson(QJsonDocument::Compact);
            sock.write(msg);
            sock.flush();
            sock.waitForBytesWritten(1000);
            nmLog(QStringLiteral("Focus message sent, exiting."));
            return 0;
        }

        if (sock.error() == QLocalSocket::ConnectionRefusedError) {
            nmLog(QStringLiteral("Found stale single-instance socket, removing it."));
            QLocalServer::removeServer(kServerName);
        } else {
            nmLog(QStringLiteral("No existing instance found."));
        }
    }

    nmLog(QStringLiteral("Registering QML types..."));
    qmlRegisterUncreatableType<DownloadTableModel>("com.stellar.app", 1, 0, "DownloadTableModel",
        QStringLiteral("Use App.downloadModel"));
    qmlRegisterUncreatableType<CategoryModel>("com.stellar.app", 1, 0, "CategoryModel",
        QStringLiteral("Use App.categoryModel"));
    qmlRegisterUncreatableType<AppSettings>("com.stellar.app", 1, 0, "AppSettings",
        QStringLiteral("Use App.settings"));
    qmlRegisterUncreatableType<YtdlpManager>("com.stellar.app", 1, 0, "YtdlpManager",
        QStringLiteral("Use App.ytdlpManager"));
    qmlRegisterUncreatableType<TorrentSearchManager>("com.stellar.app", 1, 0, "TorrentSearchManager",
        QStringLiteral("Use App.torrentSearchManager"));
    qmlRegisterUncreatableType<TorrentSearchPluginModel>("com.stellar.app", 1, 0, "TorrentSearchPluginModel",
        QStringLiteral("Use App.torrentSearchManager.pluginModel"));
    qmlRegisterUncreatableType<TorrentSearchResultModel>("com.stellar.app", 1, 0, "TorrentSearchResultModel",
        QStringLiteral("Use App.torrentSearchManager.resultModel"));
    qmlRegisterUncreatableType<RssManager>("com.stellar.app", 1, 0, "RssManager",
        QStringLiteral("Use App.rssManager"));
    qmlRegisterUncreatableType<RssFeedModel>("com.stellar.app", 1, 0, "RssFeedModel",
        QStringLiteral("Use App.rssManager.feedModel"));
    qmlRegisterUncreatableType<RssArticleModel>("com.stellar.app", 1, 0, "RssArticleModel",
        QStringLiteral("Use App.rssManager.articleModel"));
    qmlRegisterType<FileDragDropHelper>("com.stellar.app", 1, 0, "FileDragDropHelper");

    nmLog(QStringLiteral("Instantiating AppController..."));
    AppController controller;
    nmLog(QStringLiteral("AppController instantiated successfully."));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("fileicon"), new FileIconImageProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("StartMinimized"), startMinimized);
    engine.addImportPath(QLibraryInfo::path(QLibraryInfo::QmlImportsPath));

    const QUrl url(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    nmLog(QStringLiteral("Loading QML..."));
    engine.load(url);
    nmLog(QStringLiteral("QML loaded. Executing app."));

    // Schedule a zero-delay timer to fire on the FIRST event loop iteration after
    // app.exec() starts.  By that time:
    //   1. All pending QLocalSocket signals (newConnection → readyRead) have been
    //      queued by the OS and will be processed before or alongside this timer.
    //   2. The drop file (written by the native host when it couldn't reach IPC)
    //      is read here, so the payload is fed in exactly once regardless of
    //      whether the native host also delivered it via IPC.
    //
    // setQmlReady() is called inside the timer, not from Component.onCompleted,
    // because Component.onCompleted fires during engine.load() — before app.exec()
    // starts the event loop — so any IPC socket data buffered in the OS wouldn't
    // have been processed yet, and the drain would be a no-op.
    QTimer::singleShot(0, &controller, [&controller]() {
        const QString dropPath = pendingDownloadFilePath();
        QFile dropFile(dropPath);
        if (dropFile.exists() && dropFile.open(QIODevice::ReadOnly)) {
            QByteArray pending = dropFile.readAll();
            dropFile.close();
            QFile::remove(dropPath);
            if (!pending.isEmpty()) {
                nmLog(QStringLiteral("Replaying pending download from drop file (via zero-timer)"));
                controller.handleIpcPayload(pending);
            }
        }
        controller.setQmlReady();
    });

    return app.exec();
}
