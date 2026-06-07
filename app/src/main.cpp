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

#include <QApplication>
#include <QTimer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QOpenGLContext>
#include <QOffscreenSurface>
#include <QSurfaceFormat>
#include <QIcon>
#include <QLocalSocket>
#include <QLocalServer>
#include <QSharedMemory>
#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <iostream>
#include <QProcess>
#include <QThread>
#include <QFile>
#include <QDir>
#include <QUrl>
#include <QUrlQuery>
#include <QTextStream>
#include <QStandardPaths>
#include <QLibraryInfo>
#include <QLoggingCategory>
#include "AppController.h"
#include "FileIconImageProvider.h"
#include "FileDragDropHelper.h"
#include "FileIconImageProvider.h"
#include "StellarPaths.h"
#include "RssArticleModel.h"
#include "NetworkInfo.h"
#include "RssFeedModel.h"
#include "RssManager.h"
#include "TorrentSearchManager.h"
#include "TorrentSearchPluginModel.h"
#include "TorrentSearchResultModel.h"
#include <QFont>
#include <QQuickWindow>

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

// True when arg looks like a CLI switch (/x or -x) that should not be
// misinterpreted as a file path during torrent/magnet argument scanning.
static bool looksLikeCliSwitch(const QString &arg)
{
    if (arg.length() < 2)
        return false;
    const QChar first = arg.at(0);
    return (first == QLatin1Char('/') || first == QLatin1Char('-'))
        && arg.at(1).isLetter();
}

static QString localTorrentFileFromArgument(const QString &arg)
{
    const QString trimmed = arg.trimmed();
    if (trimmed.isEmpty() || looksLikeCliSwitch(trimmed) || trimmed.startsWith(QStringLiteral("--")))
        return {};

    QString candidate = trimmed;
    const QUrl maybeUrl = QUrl::fromUserInput(candidate);
    if (maybeUrl.isLocalFile())
        candidate = maybeUrl.toLocalFile();

    const QFileInfo info(QDir::fromNativeSeparators(candidate));
    if (!info.exists() || !info.isFile()
        || !info.fileName().endsWith(QStringLiteral(".torrent"), Qt::CaseInsensitive)) {
        return {};
    }
    return info.absoluteFilePath();
}

static QString magnetUriFromArgument(const QString &arg)
{
    const QString trimmed = arg.trimmed();
    if (trimmed.isEmpty() || looksLikeCliSwitch(trimmed) || trimmed.startsWith(QStringLiteral("--")))
        return {};

    return trimmed.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)
        ? trimmed
        : QString();
}

// CLI modifier flags that can accompany a bare torrent/magnet argument.
// Mirrors the non-/d fields in CliArgs so the same payload shape is used.
struct TorrentCliMods {
    QString savePath;
    QString saveFilename;
    bool    silent    = false;
    bool    addOnly   = false;
    bool    quitAfter = false;

    bool hasAny() const {
        return !savePath.isEmpty() || !saveFilename.isEmpty()
            || silent || addOnly || quitAfter;
    }
};

// Extract modifier flags from argv without requiring /d or /s.
// Caller must skip argv[0] and any arg already consumed as a download URL.
static TorrentCliMods extractTorrentMods(int argc, char *argv[], int skipIdx = -1)
{
    TorrentCliMods mod;
    for (int i = 1; i < argc; ++i) {
        if (i == skipIdx)
            continue;
        const QString arg = QString::fromLocal8Bit(argv[i]);
        auto isSwitch = [&](const char *s) {
            return arg.compare(QString::fromLatin1(s),            Qt::CaseInsensitive) == 0
                || arg.compare(QString::fromLatin1(s).replace(QLatin1Char('/'), QLatin1Char('-')), Qt::CaseInsensitive) == 0;
        };
        if (isSwitch("/p")) {
            if (i + 1 < argc)
                mod.savePath = QString::fromLocal8Bit(argv[++i]);
        } else if (isSwitch("/f")) {
            if (i + 1 < argc)
                mod.saveFilename = QString::fromLocal8Bit(argv[++i]);
        } else if (isSwitch("/q")) {
            mod.quitAfter = true;
        } else if (isSwitch("/n")) {
            mod.silent = true;
        } else if (isSwitch("/a")) {
            mod.addOnly = true;
        }
    }
    return mod;
}

// Build a cliDownload-style payload so the running instance routes the
// torrent/magnet through the same handler as /d URL (respects /p, /f, /n, etc.).
static QByteArray makeTorrentCliPayload(const QString &source, const TorrentCliMods &mod)
{
    return QJsonDocument(QJsonObject{
        {QStringLiteral("type"),      QStringLiteral("cliDownload")},
        {QStringLiteral("url"),       source},
        {QStringLiteral("savePath"),  mod.savePath},
        {QStringLiteral("filename"),  mod.saveFilename},
        {QStringLiteral("silent"),    mod.silent},
        {QStringLiteral("addOnly"),   mod.addOnly},
        {QStringLiteral("quitAfter"), mod.quitAfter},
    }).toJson(QJsonDocument::Compact);
}

// Plain payload used when no CLI modifiers are present — falls through the
// existing "download" handler so the normal interactive flow kicks in.
static QByteArray makeTorrentPlainPayload(const QString &filePath)
{
    return QJsonDocument(QJsonObject{
        {QStringLiteral("type"),     QStringLiteral("download")},
        {QStringLiteral("url"),      QDir::toNativeSeparators(QFileInfo(filePath).absoluteFilePath())},
        {QStringLiteral("filename"), QFileInfo(filePath).fileName()}
    }).toJson(QJsonDocument::Compact);
}

static QByteArray makeMagnetPlainPayload(const QString &magnetUri)
{
    QString filename = QStringLiteral("Magnetized transfer");
    if (magnetUri.startsWith(QStringLiteral("magnet:?"), Qt::CaseInsensitive)) {
        QUrlQuery query(QUrl(magnetUri).query());
        const QString dn = query.queryItemValue(QStringLiteral("dn"));
        if (!dn.isEmpty())
            filename = dn.trimmed();
    }
    return QJsonDocument(QJsonObject{
        {QStringLiteral("type"),     QStringLiteral("download")},
        {QStringLiteral("url"),      magnetUri},
        {QStringLiteral("filename"), filename}
    }).toJson(QJsonDocument::Compact);
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

// ── IDM-compatible CLI mode ───────────────────────────────────────────────────
// Stellar.exe /d URL [/p path] [/f filename] [/q] [/h] [/n] [/a]
// Stellar.exe /s
//
// /d URL  - download a file
// /s      - start the queue in scheduler
// /p path - local directory to save the file
// /f name - local filename to save the file
// /q      - quit Stellar after successful download (first copy only)
// /n      - silent mode (no UI prompts)
// /a      - add to queue but do not start downloading

struct CliArgs {
    bool        isCli       = false;  // true when any IDM-style switch is present
    bool        startSched  = false;  // /s
    QString     downloadUrl;          // /d URL
    QString     savePath;             // /p path
    QString     saveFilename;         // /f filename
    bool        quitAfter   = false;  // /q
    bool        silent      = false;  // /n
    bool        addOnly     = false;  // /a (add to queue, don't start)
};

static CliArgs parseCliArgs(int argc, char *argv[])
{
    CliArgs ca;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        // Accept both /switch and -switch for robustness.
        auto isSwitch = [&](const char *s) {
            return arg.compare(QString::fromLatin1(s),            Qt::CaseInsensitive) == 0
                || arg.compare(QString::fromLatin1(s).replace(QLatin1Char('/'), QLatin1Char('-')), Qt::CaseInsensitive) == 0;
        };

        if (isSwitch("/s")) {
            ca.isCli = true;
            ca.startSched = true;
        } else if (isSwitch("/d")) {
            ca.isCli = true;
            if (i + 1 < argc)
                ca.downloadUrl = QString::fromLocal8Bit(argv[++i]);
        } else if (isSwitch("/p")) {
            if (i + 1 < argc)
                ca.savePath = QString::fromLocal8Bit(argv[++i]);
        } else if (isSwitch("/f")) {
            if (i + 1 < argc)
                ca.saveFilename = QString::fromLocal8Bit(argv[++i]);
        } else if (isSwitch("/q")) {
            ca.quitAfter = true;
        } else if (isSwitch("/n")) {
            ca.silent = true;
        } else if (isSwitch("/a")) {
            ca.addOnly = true;
        }
    }
    return ca;
}

// Build the IPC JSON payload for a CLI download command.
static QByteArray makeCliDownloadPayload(const CliArgs &ca)
{
    QJsonObject obj;
    obj[QStringLiteral("type")]     = QStringLiteral("cliDownload");
    obj[QStringLiteral("url")]      = ca.downloadUrl;
    obj[QStringLiteral("savePath")] = ca.savePath;
    obj[QStringLiteral("filename")] = ca.saveFilename;
    obj[QStringLiteral("silent")]   = ca.silent;
    obj[QStringLiteral("addOnly")]  = ca.addOnly;
    obj[QStringLiteral("quitAfter")]= ca.quitAfter;
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

// Build the IPC JSON payload for /s (start scheduler / default queue).
static QByteArray makeCliStartSchedulerPayload()
{
    return QJsonDocument(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("cliStartScheduler")}
    }).toJson(QJsonDocument::Compact);
}

// Run CLI mode: forward the command to a running instance via IPC, or launch
// the GUI with the payload stored in the drop file (same cold-start pattern
// used by the native messaging host).
static int runCliMode(int argc, char *argv[], const CliArgs &ca)
{
    QCoreApplication coreApp(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("Stellar"));
    QCoreApplication::setOrganizationName(QStringLiteral("Stellar"));

    const QByteArray payload = ca.startSched
        ? makeCliStartSchedulerPayload()
        : makeCliDownloadPayload(ca);

    const QString kServer = QStringLiteral("StellarDownloadManager");
    QLocalSocket sock;
    sock.connectToServer(kServer);

    if (sock.waitForConnected(500)) {
        // Running instance found -- forward the command and exit.
        sock.write(payload);
        sock.flush();
        sock.waitForBytesWritten(3000);
        return 0;
    }

    // No running instance.  For download commands, persist the payload so the
    // GUI can replay it via the same drop-file mechanism the native host uses.
    if (!ca.startSched) {
        QFile dropFile(pendingDownloadFilePath());
        if (dropFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
            dropFile.write(payload);
    }

    // Launch the GUI.  On Windows, try to break out of any Job Object first.
    const QString program = QCoreApplication::applicationFilePath();
    QStringList guiArgs = {QStringLiteral("--gui")};
    if (ca.silent)
        guiArgs << QStringLiteral("--minimized");

#if defined(Q_OS_WIN)
    {
        QString cmdLine = QStringLiteral("\"%1\"").arg(program);
        for (const QString &a : guiArgs)
            cmdLine += QStringLiteral(" ") + a;
        std::wstring cmdW = cmdLine.toStdWString();
        STARTUPINFOW si = {};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi = {};
        const DWORD flags = CREATE_BREAKAWAY_FROM_JOB | CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS;
        if (!CreateProcessW(nullptr, cmdW.data(), nullptr, nullptr,
                            FALSE, flags, nullptr, nullptr, &si, &pi)) {
            QProcess::startDetached(program, guiArgs);
        } else {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
    }
#else
    QProcess::startDetached(program, guiArgs);
#endif

    // For /s (scheduler start) with no running instance, try to connect once
    // the GUI has had time to start.
    if (ca.startSched) {
        for (int i = 0; i < 40; ++i) {
            QThread::msleep(500);
            sock.connectToServer(kServer);
            if (sock.waitForConnected(500)) {
                sock.write(payload);
                sock.flush();
                sock.waitForBytesWritten(3000);
                break;
            }
        }
    }

    return 0;
}

// ── GUI mode ──────────────────────────────────────────────────────────────────

// Probe hardware OpenGL in-process, before any QQuickWindow exists. Qt Quick's
// default RHI backend is OpenGL; if a GL context can't be created (VirtualBox
// SVGA3D with no usable FBConfig, Wayland without EGL, headless/RDP, broken Mesa)
// Qt qFatal()s on the first window. Creating a throwaway context on a hidden
// QOffscreenSurface lets us detect that and select the software scene graph up
// front, so the app opens (on the GPU when it can, on the CPU when it must)
// instead of crashing.
static bool probeOpenGl()
{
    QOpenGLContext ctx;
    QOffscreenSurface surface;
    surface.setFormat(QSurfaceFormat::defaultFormat());
    surface.create();
    if (!surface.isValid())
        return false;
    if (!ctx.create())
        return false;
    if (!ctx.makeCurrent(&surface))
        return false;
    ctx.doneCurrent();
    return true;
}

static void selectWorkingGraphicsBackend()
{
#if defined(Q_OS_LINUX)
    if (!qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND") ||
        !qEnvironmentVariableIsEmpty("QSG_RHI_BACKEND")) {
        return; // explicit backend choice — leave it alone
    }

    if (probeOpenGl())
        return; // hardware GL works with the current default format

    // The default QSurfaceFormat may have no matching GLX FBConfig on this driver
    // (VirtualBox/SVGA3D, bare Mesa: "qglx_findConfig: Failed ... matching
    // FBConfig") while a leaner format works. Retry once with a minimal,
    // widely-supported format before falling back to software.
    {
        QSurfaceFormat fmt;
        fmt.setRenderableType(QSurfaceFormat::OpenGL);
        fmt.setProfile(QSurfaceFormat::NoProfile);
        fmt.setRedBufferSize(8);
        fmt.setGreenBufferSize(8);
        fmt.setBlueBufferSize(8);
        fmt.setAlphaBufferSize(0);
        fmt.setDepthBufferSize(24);
        fmt.setStencilBufferSize(0);
        fmt.setSamples(0);
        fmt.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
        QSurfaceFormat::setDefaultFormat(fmt);
    }

    if (probeOpenGl()) {
        nmLog(QStringLiteral("Hardware OpenGL works with a minimal surface format."));
        return; // good — keep hardware GL with the conservative format
    }

    nmLog(QStringLiteral("Hardware OpenGL unavailable; using software scene graph."));
    // No usable GL. Select the software backend; the env vars cover the code paths
    // (and the xcb GL probe) that read them directly so nothing retries GLX/EGL.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    qputenv("QT_QUICK_BACKEND", "software");
    qputenv("QT_XCB_GL_INTEGRATION", "none");
#endif
}

int main(int argc, char *argv[])
{
    // Silence Qt's harmless "OpenType support missing ... script 20" font-DB
    // warnings -- Qt logs these for scripts (e.g. Braille) no installed UI font
    // shapes. They're cosmetic noise, not a real problem.
    QLoggingCategory::setFilterRules(QStringLiteral("qt.text.font.db.warning=false"));

    QString argsStr;
    QString launchTorrentFile;
    QString launchMagnetUri;
    for (int i = 0; i < argc; ++i) {
        argsStr += QString::fromUtf8(argv[i]) + " ";
        if (i > 0 && launchTorrentFile.isEmpty() && launchMagnetUri.isEmpty()) {
            const QString arg = QString::fromLocal8Bit(argv[i]);
            launchTorrentFile = localTorrentFileFromArgument(arg);
            if (launchTorrentFile.isEmpty())
                launchMagnetUri = magnetUriFromArgument(arg);
        }
    }
    nmLog(QStringLiteral("App started with args: ") + argsStr);

    bool forceGui = false;
    bool startMinimized = false;
    bool isRelaunch = false;
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], "--gui") == 0)
            forceGui = true;
        else if (qstrcmp(argv[i], "--minimized") == 0)
            startMinimized = true;
        else if (qstrcmp(argv[i], "--relaunch") == 0)
            isRelaunch = true;
    }

    // Parse IDM-compatible CLI switches.  If any are present and --gui was not
    // explicitly requested, run in CLI mode (no GUI window opened by this copy).
    const CliArgs cliArgs = parseCliArgs(argc, argv);
    if (cliArgs.isCli && !forceGui)
        return runCliMode(argc, argv, cliArgs);
    
    nmLog(QStringLiteral("App startup. forceGui=") + (forceGui ? "true" : "false"));
    nmLog(QStringLiteral("Checking for existing instance..."));
    
    // Detect native-messaging mode before constructing QGuiApplication — it
    // would try to connect to a display that doesn't exist in a subprocess.
    if (!forceGui && stdinIsPipe()) {
        nmLog(QStringLiteral("stdinIsPipe=true, entering native host mode"));
        return runNativeMessagingHost(argc, argv);
    }

    // Set application/organization names early so StellarPaths::root() (which
    // depends on QStandardPaths::AppLocalDataLocation and on the org/app name
    // for its suffix-stripping) resolves to the real settings directory below.
    // Without this, the pre-QApplication QSettings reads fall back to a
    // different path and the scale/font overrides silently never apply on
    // Linux. These are static setters and don't require a QApplication.
    QCoreApplication::setApplicationName(QStringLiteral("Stellar"));
    QCoreApplication::setOrganizationName(QStringLiteral("Stellar"));

    // Apply UI scale factor before QApplication — Qt reads QT_SCALE_FACTOR
    // at construction time and ignores it afterwards. Always unset first so a
    // restart (which inherits the parent process's environment via
    // QProcess::startDetached) doesn't keep a previously-set scale when the
    // user picks "System default".
    {
        QSettings s(StellarPaths::settingsFile(), QSettings::IniFormat);
        const double scale = s.value(QStringLiteral("uiScaleFactor"), 0.0).toDouble();
        qunsetenv("QT_SCALE_FACTOR");
        if (scale >= 0.5 && scale <= 3.0)
            qputenv("QT_SCALE_FACTOR", QString::number(scale, 'f', 2).toUtf8());
    }

    nmLog(QStringLiteral("Constructing QGuiApplication..."));
    QApplication app(argc, argv);
    nmLog(QStringLiteral("QGuiApplication constructed."));

    // Stellar is a tray app: its lifetime is controlled explicitly (tray Quit,
    // quitApp(), requestQuit()), never by Qt's "last window closed" heuristic.
    // Disabling this is required for the cold-start intercept flow — the main
    // window stays hidden and only the New Download dialog is shown, so closing
    // that dialog must NOT be treated as "last window closed → quit". The
    // main-window close path quits explicitly in Main.qml onClosing instead.
    app.setQuitOnLastWindowClosed(false);

    // Pick a scene-graph backend that actually works on this display before any
    // QQuickWindow is created. Prevents the "Could not initialize GLX" /
    // "EGL not available" qFatal abort on machines without usable hardware GL
    // (VMs, Wayland-without-EGL, headless, broken drivers). See helper above.
    selectWorkingGraphicsBackend();

    // Apply base font size — must be after QApplication construction.
    {
        QSettings s(StellarPaths::settingsFile(), QSettings::IniFormat);
        const int fontSize = s.value(QStringLiteral("uiFontPointSize"), 0).toInt();
        if (fontSize >= 6 && fontSize <= 32) {
            QFont f = app.font();
            f.setPointSize(fontSize);
            app.setFont(f);
        }
    }
    
    app.setApplicationName(QStringLiteral("Stellar"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("Stellar"));
    // desktopFileName lets KDE/Wayland compositors resolve the window icon from
    // the installed .desktop file instead of relying on the in-process icon.
    app.setDesktopFileName(QStringLiteral("io.github.stellar.Stellar"));
    const QIcon appIcon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/milky-way.png"));
    app.setWindowIcon(appIcon);

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

    // Build the torrent/magnet IPC payload once, incorporating any CLI modifier
    // flags (/n, /a, /q, /p, /f) that may accompany a bare torrent/magnet argument.
    QByteArray launchTorrentPayload;
    QByteArray launchMagnetPayload;
    if (!launchTorrentFile.isEmpty()) {
        const TorrentCliMods mod = extractTorrentMods(argc, argv);
        launchTorrentPayload = mod.hasAny()
            ? makeTorrentCliPayload(launchTorrentFile, mod)
            : makeTorrentPlainPayload(launchTorrentFile);
    } else if (!launchMagnetUri.isEmpty()) {
        const TorrentCliMods mod = extractTorrentMods(argc, argv);
        launchMagnetPayload = mod.hasAny()
            ? makeTorrentCliPayload(launchMagnetUri, mod)
            : makeMagnetPlainPayload(launchMagnetUri);
    }

    // Single-instance guard.
    // QLocalSocket alone has a race: two processes launched simultaneously
    // both see no server and both proceed. QSharedMemory::create() is atomic
    // at the OS level — only one caller can succeed.
    const QString kServerName = QStringLiteral("StellarDownloadManager");
    QSharedMemory shm(QStringLiteral("StellarSingleInstance"));
    bool weOwnSegment = shm.create(1);

    // Restart path: this process was spawned by App.restartApp() while the old
    // instance was still tearing down, so its single-instance segment may still
    // be held for a moment. Wait for the parent to release it instead of
    // mistaking ourselves for a duplicate and exiting. The segment is freed by
    // the OS once the old process closes its last handle.
    if (!weOwnSegment && isRelaunch && shm.error() == QSharedMemory::AlreadyExists) {
        nmLog(QStringLiteral("Relaunch: waiting for previous instance to exit..."));
        for (int waited = 0; waited < 10000 && !weOwnSegment; waited += 100) {  // up to 10 s
            QThread::msleep(100);
            weOwnSegment = shm.create(1);       // succeeds once the parent frees it
        }
        QLocalServer::removeServer(kServerName); // drop the parent's stale socket
    }

    if (!weOwnSegment && shm.error() == QSharedMemory::AlreadyExists) {
        nmLog(QStringLiteral("Single-instance segment exists. Probing live instance..."));
        QLocalSocket sock;
        sock.connectToServer(kServerName);
        if (sock.waitForConnected(500)) {
            const bool shouldOpenTorrent = !launchTorrentFile.isEmpty();
            const bool shouldOpenMagnet = !launchMagnetUri.isEmpty();
            nmLog((shouldOpenTorrent || shouldOpenMagnet)
                      ? QStringLiteral("Existing instance found, sending torrent-open message...")
                      : QStringLiteral("Existing instance found, sending focus message..."));
            const QByteArray msg = shouldOpenTorrent
                ? launchTorrentPayload
                : shouldOpenMagnet
                    ? launchMagnetPayload
                : QJsonDocument(QJsonObject{{QStringLiteral("type"), QStringLiteral("focus")}})
                      .toJson(QJsonDocument::Compact);
            sock.write(msg);
            sock.flush();
            sock.waitForBytesWritten(1000);
            nmLog((shouldOpenTorrent || shouldOpenMagnet)
                      ? QStringLiteral("Torrent-open message sent, exiting.")
                      : QStringLiteral("Focus message sent, exiting."));
            return 0;
        }

        // Segment exists but nobody is listening on the IPC socket: the previous
        // instance crashed without freeing it. On Linux QSharedMemory uses a SysV
        // segment that is not reclaimed on abnormal exit, so the stale key would
        // otherwise block every future launch. Reclaim it: attach()+detach() makes
        // us the last attacher, and Qt removes the segment on final detach.
        nmLog(QStringLiteral("Stale single-instance segment from a crashed instance; reclaiming."));
        if (shm.attach()) {
            shm.detach();              // last detach removes the orphaned SysV segment
        }
        weOwnSegment = shm.create(1);  // retry now that the stale key is gone
        if (!weOwnSegment) {
            // Still couldn't take ownership — a genuine race with another
            // starting instance, or an unrecoverable IPC state. Fail rather
            // than run two copies against the same on-disk database.
            nmLog(QStringLiteral("Could not reclaim single-instance segment. Exiting."));
            return 1;
        }
    }
    // First instance — shm stays alive on main()'s stack until app.exec() returns.
    // Clean up any stale server socket from a previous crashed instance.
    QLocalServer::removeServer(kServerName);

    // Install the saved translator before AppController is constructed so
    // QObject-based defaults created during controller/model setup (like
    // built-in category labels) are translated from the start.
    QTranslator startupTranslator;
    QString savedLocale;
    {
        QSettings settings(StellarPaths::settingsFile(), QSettings::IniFormat);
        savedLocale = settings.value(QStringLiteral("uiLanguage")).toString().trimmed();
        if (!savedLocale.isEmpty()) {
            const QString qmPath = QStringLiteral(":/i18n/stellar_%1").arg(savedLocale);
            if (startupTranslator.load(qmPath))
                QCoreApplication::installTranslator(&startupTranslator);
            else
                qWarning() << "[i18n] Failed to preload translation for locale:" << savedLocale;
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
    qmlRegisterUncreatableType<NetworkInfo>("com.stellar.app", 1, 0, "NetworkInfo",
        QStringLiteral("Use App.networkInfo"));

    nmLog(QStringLiteral("Instantiating AppController..."));
    AppController controller;
    nmLog(QStringLiteral("AppController instantiated successfully."));

    // Load saved UI language before the QML engine starts so that qsTr() calls
    // in QML component construction pick up the correct translator.
    if (!savedLocale.isEmpty())
        controller.applyUiLanguage(savedLocale);

    // A pending-download drop file present at startup means this GUI copy was
    // cold-started by the native host purely to service an intercepted download.
    // In that case the user only wants the New Download dialog — keep the main
    // window hidden so we don't pop the whole app to the foreground.
    const bool launchedForDownload = QFile::exists(pendingDownloadFilePath());

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("fileicon"), new FileIconImageProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("StartMinimized"), startMinimized);
    engine.rootContext()->setContextProperty(QStringLiteral("LaunchedForDownload"), launchedForDownload);
    engine.addImportPath(QLibraryInfo::path(QLibraryInfo::QmlImportsPath));

    const QUrl url(QStringLiteral("qrc:/qt/qml/com/stellar/app/app/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    nmLog(QStringLiteral("Loading QML..."));
    engine.load(url);
    nmLog(QStringLiteral("QML loaded. Executing app."));

    // Keep scene graph and D3D/GL resources alive when the window is minimized
    // or hidden so the first paint after restore is just a swap, not a full
    // scene graph rebuild + swap chain recreation (which was taking ~1-2s on
    // Windows D3D11 with a large download list).
    if (!engine.rootObjects().isEmpty()) {
        if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst())) {
            win->setPersistentSceneGraph(true);
            win->setPersistentGraphics(true);
            // On Linux/KDE QQuickWindows don't inherit the application icon —
            // set it explicitly so every window (main + dialogs) shows the icon.
            win->setIcon(appIcon);
        }
    }

#if defined(Q_OS_LINUX)
    // Propagate the app icon to all QQuickWindows created after engine load
    // (dialogs, property windows, etc.) since QQuickWindow doesn't inherit
    // QGuiApplication::windowIcon automatically on Wayland/KDE.
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &engine,
        [&appIcon](QObject *obj, const QUrl &) {
            if (auto *win = qobject_cast<QQuickWindow *>(obj))
                win->setIcon(appIcon);
        });
#endif

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
    QTimer::singleShot(0, &controller, [&controller, launchTorrentPayload, launchMagnetPayload]() {
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
        if (!launchTorrentPayload.isEmpty()) {
            nmLog(QStringLiteral("Replaying startup torrent-open payload from command line"));
            controller.handleIpcPayload(launchTorrentPayload);
        } else if (!launchMagnetPayload.isEmpty()) {
            nmLog(QStringLiteral("Replaying startup magnet-open payload from command line"));
            controller.handleIpcPayload(launchMagnetPayload);
        }
        controller.setQmlReady();
    });

    return app.exec();
}
