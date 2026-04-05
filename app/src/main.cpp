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
#include <QCoreApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QLibraryInfo>
#include <QLocalSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSettings>
#include <QFile>
#include <QDir>
#include <QDateTime>
#include "AppController.h"
#include "DownloadTableModel.h"
#include "CategoryModel.h"
#include "AppSettings.h"
#include "FileDragDropHelper.h"

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
#if defined(Q_OS_WIN)
    const QString path = QString::fromLocal8Bit(qgetenv("TEMP")) + QStringLiteral("\\stellar_nm.log");
#else
    const QString path = QStringLiteral("/tmp/stellar_nm.log");
#endif
    QFile f(path);
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        f.write(QDateTime::currentDateTime().toString(Qt::ISODate).toUtf8());
        f.write(" ");
        f.write(msg.toUtf8());
        f.write("\n");
    }
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
        if (sock.waitForConnected(3000)) {
            sock.write(payload);
            sock.flush();
            sock.waitForBytesWritten(3000);
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
    // Detect native-messaging mode before constructing QGuiApplication — it
    // would try to connect to a display that doesn't exist in a subprocess.
    if (stdinIsPipe()) {
        nmLog(QStringLiteral("stdinIsPipe=true, entering native host mode"));
        return runNativeMessagingHost(argc, argv);
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Stellar Download Manager"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("StellarProject"));
    app.setWindowIcon(QIcon(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/icons/milky-way.png")));

    qmlRegisterUncreatableType<DownloadTableModel>("com.stellar.app", 1, 0, "DownloadTableModel",
        QStringLiteral("Use App.downloadModel"));
    qmlRegisterUncreatableType<CategoryModel>("com.stellar.app", 1, 0, "CategoryModel",
        QStringLiteral("Use App.categoryModel"));
    qmlRegisterUncreatableType<AppSettings>("com.stellar.app", 1, 0, "AppSettings",
        QStringLiteral("Use App.settings"));
    qmlRegisterType<FileDragDropHelper>("com.stellar.app", 1, 0, "FileDragDropHelper");

    AppController controller;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &controller);
    engine.addImportPath(QLibraryInfo::path(QLibraryInfo::QmlImportsPath));

    const QUrl url(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
