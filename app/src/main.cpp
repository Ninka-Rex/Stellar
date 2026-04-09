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
#include <QLibraryInfo>
#include "AppController.h"
#include "FileIconImageProvider.h"
#include "FileDragDropHelper.h"
#include "FileIconImageProvider.h"

#if defined(Q_OS_WIN)
#  include <windows.h>
#else
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
    return !isatty(STDIN_FILENO);
}

#endif  // Q_OS_WIN

static void writeNativeMsg(const QByteArray &json)
{
    quint32 len = static_cast<quint32>(json.size());
    nmWrite(reinterpret_cast<const char *>(&len), 4);
    nmWrite(json.constData(), len);
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

    if (type == QStringLiteral("download") || type == QStringLiteral("focus")) {
        QLocalSocket sock;
        sock.connectToServer(QStringLiteral("StellarDownloadManager"));
        if (!sock.waitForConnected(500)) {
            // Main app isn't running, we need to start it.
            nmLog(QStringLiteral("Main app not running, launching it now..."));
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
              
              // Give it some time to start the IPC server
            bool connected = false;
            for (int i = 0; i < 10; ++i) {
                QThread::msleep(300);
                sock.connectToServer(QStringLiteral("StellarDownloadManager"));
                if (sock.waitForConnected(500)) {
                    connected = true;
                    break;
                }
            }
            if (!connected) {
                nmLog(QStringLiteral("Failed to connect to newly launched app"));
            }
        }
        
        if (sock.state() == QLocalSocket::ConnectedState) {
            sock.write(payload);
            sock.flush();
            sock.waitForBytesWritten(3000);
            nmLog(QStringLiteral("Successfully forwarded payload to main app"));
        }
        
        // Always ack so the extension Promise resolves cleanly.
        writeNativeMsg(QJsonDocument(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("ack")}
        }).toJson(QJsonDocument::Compact));
        return 0;
    }

    if (type == QStringLiteral("getSettings")) {
        // Read settings directly from QSettings — no need for the running app.
        // This means changes saved by the app are immediately visible to the extension.
        QSettings s(QStringLiteral("StellarProject"), QStringLiteral("Stellar"));

        auto toJsonArray = [&](const QString &key, const QStringList &defaultVal) -> QJsonArray {
            QVariant v = s.value(key);
            QStringList list = v.isValid() ? v.toStringList() : defaultVal;
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
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], "--gui") == 0) {
            forceGui = true;
            break;
        }
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
    
    app.setApplicationName(QStringLiteral("Stellar Download Manager"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("StellarProject"));
    app.setWindowIcon(QIcon(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/icons/milky-way.png")));

    // Single-instance guard: try to reach an already-running instance.
    QLocalServer::removeServer(QStringLiteral("StellarDownloadManager"));
    {
        nmLog(QStringLiteral("Connecting to existing instance socket..."));
        QLocalSocket sock;
        sock.connectToServer(QStringLiteral("StellarDownloadManager"));
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
        nmLog(QStringLiteral("No existing instance found."));
    }

    nmLog(QStringLiteral("Registering QML types..."));
    qmlRegisterUncreatableType<DownloadTableModel>("com.stellar.app", 1, 0, "DownloadTableModel",
        QStringLiteral("Use App.downloadModel"));
    qmlRegisterUncreatableType<CategoryModel>("com.stellar.app", 1, 0, "CategoryModel",
        QStringLiteral("Use App.categoryModel"));
    qmlRegisterUncreatableType<AppSettings>("com.stellar.app", 1, 0, "AppSettings",
        QStringLiteral("Use App.settings"));
    qmlRegisterType<FileDragDropHelper>("com.stellar.app", 1, 0, "FileDragDropHelper");

    nmLog(QStringLiteral("Instantiating AppController..."));
    AppController controller;
    nmLog(QStringLiteral("AppController instantiated successfully."));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("fileicon"), new FileIconImageProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &controller);
    engine.addImportPath(QLibraryInfo::path(QLibraryInfo::QmlImportsPath));

    const QUrl url(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    nmLog(QStringLiteral("Loading QML..."));
    engine.load(url);
    nmLog(QStringLiteral("QML loaded. Executing app."));

    return app.exec();
}
