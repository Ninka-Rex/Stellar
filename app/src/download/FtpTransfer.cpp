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

#include "FtpTransfer.h"
#include "FileNameUtils.h"

#include <QTcpSocket>
#include <QSslSocket>
#include <QSslConfiguration>
#include <QSslError>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStringList>
#include <QHostAddress>
#include <QRegularExpression>
#include <QtConcurrent/QtConcurrent>
#include <QFutureWatcher>
#include <QPointer>
#include <algorithm>

static constexpr qint64 kFtpMapWindow = 256LL * 1024 * 1024;

// ─────────────────────────────────────────────────────────────────────────────
// FtpControl — one persistent control connection plus its data connection.
//
// Lifecycle, driven by the owner (FtpTransfer):
//   1. start()           → connect, [AUTH TLS], USER/PASS, [PBSZ/PROT], TYPE I,
//                          optionally SIZE, then emit ready(size, /*loggedIn*/).
//   2. retrieve(off,end) → PASV/EPSV, [REST off], RETR; stream into the data
//                          socket. dataReady() fires as bytes arrive; completed()
//                          when the 226/250 final reply is seen.
//
// FTP permits only one RETR per control channel, so each parallel byte range
// owns its own FtpControl. Every server reply is validated; the passive data
// connection is always dialled to the control peer IP (only the advertised port
// is trusted) to defeat PASV-bounce / FXP.
// ─────────────────────────────────────────────────────────────────────────────
class FtpControl : public QObject {
    Q_OBJECT
public:
    enum class Phase {
        Connecting, Greeting, AuthTls, User, Pass, Pbsz, Prot, Type, Size,
        Idle,                 // logged in, waiting for retrieve()
        Pasv, Rest, Retr, Transferring, Done, Failed
    };

    FtpControl(const QUrl &url, QString user, QString pass, bool secure,
               bool wantSize, int timeoutMs, QObject *parent = nullptr)
        : QObject(parent), m_url(url), m_user(std::move(user)), m_pass(std::move(pass)),
          m_secure(secure), m_wantSize(wantSize), m_timeoutMs(timeoutMs)
    {
        m_timer = new QTimer(this);
        m_timer->setSingleShot(true);
        connect(m_timer, &QTimer::timeout, this, &FtpControl::onTimeout);
    }

    ~FtpControl() override {
        if (m_data)    m_data->abort();
        if (m_control) m_control->abort();
    }

    void start() {
        m_phase = Phase::Connecting;
        m_control = new QSslSocket(this);   // speaks plaintext until startClientEncryption()
        connect(m_control, &QAbstractSocket::connected, this, [this]() { m_phase = Phase::Greeting; armTimer(); });
        connect(m_control, &QIODevice::readyRead, this, &FtpControl::onControlReadyRead);
        connect(m_control, &QAbstractSocket::errorOccurred, this, [this](QAbstractSocket::SocketError){
            failWith(tr("FTP control connection failed: %1").arg(m_control->errorString()), true); });
        connect(m_control, &QAbstractSocket::disconnected, this, [this]() {
            if (m_phase != Phase::Done && m_phase != Phase::Failed && m_phase != Phase::Idle)
                failWith(tr("FTP control connection closed unexpectedly."), true); });
        armTimer();
        const int p = m_url.port(21);
        m_control->connectToHost(m_url.host(), p <= 0 ? 21 : static_cast<quint16>(p));
    }

    // Begin retrieving the byte range [startOffset, endOffset] (endOffset = -1
    // means stream to EOF). Must be called after ready() has fired.
    void retrieve(qint64 startOffset, qint64 endOffset) {
        m_startOffset = startOffset;
        m_endOffset   = endOffset;
        beginPassive();
    }

    void setManualDataPump(bool manual) { m_manualPump = manual; }

    QSslSocket  *dataSocket()   const { return m_data; }
    QHostAddress controlPeer()  const { return m_control ? m_control->peerAddress() : QHostAddress(); }
    qint64       reportedSize() const { return m_reportedSize; }
    bool         restAccepted() const { return m_restAccepted; }

signals:
    void ready(qint64 sizeBytes);          // login (+ optional SIZE) complete
    void dataReady();                      // bytes available on the data socket
    void completed();                      // 226/250 final reply received
    void failed(const QString &reason, bool transient);

private slots:
    void onTimeout() {
        if (m_phase == Phase::Done || m_phase == Phase::Failed || m_phase == Phase::Transferring) return;
        failWith(tr("FTP control connection timed out."), true);
    }

    void onControlReadyRead() {
        while (m_control->canReadLine()) {
            if (!appendReplyLine(m_control->readLine())) continue;
            const int code = m_replyCode;
            const QString text = m_replyText;
            m_replyCode = 0; m_replyText.clear(); m_inMultiline = false;
            handleReply(code, text);
            if (m_phase == Phase::Failed) return;
        }
    }

private:
    void armTimer() { m_timer->start(m_timeoutMs); }

    bool appendReplyLine(const QByteArray &rawLine) {
        // Strip ONLY the trailing CR/LF — never the trailing space. A multiline
        // reply terminates with "NNN<space>" (often with empty text, e.g. the
        // bare "220 " that ends a multiline welcome banner); trimming the space
        // would make that line indistinguishable from a "NNN-" continuation and
        // the parser would wait forever for a terminator that already arrived.
        QString line = QString::fromUtf8(rawLine);
        while (line.endsWith(QLatin1Char('\n')) || line.endsWith(QLatin1Char('\r')))
            line.chop(1);
        if (line.isEmpty()) return false;
        static const QRegularExpression head(QStringLiteral("^(\\d{3})([ -])(.*)$"));
        const QRegularExpressionMatch m = head.match(line);

        if (!m_inMultiline) {
            if (!m.hasMatch()) return false;
            const int code = m.captured(1).toInt();
            if (code < 100 || code > 599) { failWith(tr("Malformed FTP reply."), false); return false; }
            if (m.captured(2) == QStringLiteral("-")) {
                m_inMultiline = true; m_mlCode = code; m_replyText = m.captured(3);
                return false;
            }
            m_replyCode = code; m_replyText = m.captured(3);
            return true;
        }
        if (m.hasMatch() && m.captured(2) == QStringLiteral(" ") && m.captured(1).toInt() == m_mlCode) {
            m_replyCode = m_mlCode; m_replyText += QLatin1Char('\n') + m.captured(3);
            return true;
        }
        m_replyText += QLatin1Char('\n') + line;
        return false;
    }

    void send(const QString &cmd) {
        if (cmd.contains(QLatin1Char('\r')) || cmd.contains(QLatin1Char('\n'))) {
            failWith(tr("Refusing to send FTP command with embedded newline."), false);
            return;
        }
        m_control->write(cmd.toUtf8() + "\r\n");
        armTimer();
    }

    void handleReply(int code, const QString &text) {
        const int cls = code / 100;
        switch (m_phase) {
        case Phase::Greeting:
            if (code == 220) {
                if (m_secure) { m_phase = Phase::AuthTls; send(QStringLiteral("AUTH TLS")); }
                else          { m_phase = Phase::User;    sendUser(); }
            } else failWith(serverMsg(tr("FTP server refused connection"), text), false);
            break;

        case Phase::AuthTls:
            if (code == 234) {
                installSslDiagnostics(m_control);
                connect(m_control, &QSslSocket::encrypted, this, [this]() { m_phase = Phase::User; sendUser(); });
                m_control->startClientEncryption();
            } else failWith(tr("FTPS required but the server does not support AUTH TLS."), false);
            break;

        case Phase::User:
            if (code == 230)      afterLogin();
            else if (code == 331) { m_phase = Phase::Pass; send(QStringLiteral("PASS %1").arg(passOrAnon())); }
            else                  failWith(loginError(text), false);
            break;

        case Phase::Pass:
            if (code == 230) afterLogin();
            else             failWith(loginError(text), false);
            break;

        case Phase::Pbsz:
            if (cls == 2) { m_phase = Phase::Prot; send(QStringLiteral("PROT P")); }
            else          failWith(tr("FTPS data protection (PBSZ) was rejected."), false);
            break;

        case Phase::Prot:
            if (cls == 2) { m_phase = Phase::Type; send(QStringLiteral("TYPE I")); }
            else          failWith(tr("FTPS data protection (PROT P) was rejected."), false);
            break;

        case Phase::Type:
            if (cls == 2) {
                if (m_wantSize) { m_phase = Phase::Size; send(QStringLiteral("SIZE %1").arg(m_url.path())); }
                else            { m_phase = Phase::Idle; emit ready(-1); }
            } else failWith(tr("FTP server rejected binary mode (TYPE I)."), false);
            break;

        case Phase::Size:
            if (code == 213) parseSize(text);
            else             m_reportedSize = -1;  // SIZE unsupported → unknown length
            m_phase = Phase::Idle;
            emit ready(m_reportedSize);
            break;

        case Phase::Pasv:
            if (code == 227 || code == 229) openDataConnection(code, text);
            else failWith(tr("Could not enter FTP passive mode."), true);
            break;

        case Phase::Rest:
            if (code == 350) { m_restAccepted = true; sendRetr(); }
            else {
                m_restAccepted = false;
                if (m_startOffset > 0) failWith(tr("FTP server does not support resume (REST)."), true);
                else                   sendRetr();
            }
            break;

        case Phase::Retr:
            if (code == 150 || code == 125) { m_phase = Phase::Transferring; m_timer->stop(); }
            else if (cls == 5) failWith(serverMsg(tr("FTP server rejected the file"), text), code == 530);
            else               failWith(serverMsg(tr("Unexpected FTP reply to RETR"), text), true);
            break;

        case Phase::Transferring:
            if (code == 226 || code == 250) { m_phase = Phase::Done; m_timer->stop(); emit completed(); }
            else if (cls == 4 || cls == 5)  failWith(serverMsg(tr("FTP transfer aborted by server"), text), true);
            break;

        default: break;
        }
    }

    void sendUser()  { send(QStringLiteral("USER %1").arg(userOrAnon())); }
    void afterLogin(){ if (m_secure) { m_phase = Phase::Pbsz; send(QStringLiteral("PBSZ 0")); }
                       else          { m_phase = Phase::Type; send(QStringLiteral("TYPE I")); } }
    void sendRetr()  { m_phase = Phase::Retr; send(QStringLiteral("RETR %1").arg(m_url.path())); }

    void beginPassive() { m_phase = Phase::Pasv; send(QStringLiteral("EPSV")); }

    void parseSize(const QString &text) {
        bool ok = false;
        const qint64 n = text.trimmed().section(QLatin1Char(' '), 0, 0).toLongLong(&ok);
        m_reportedSize = (ok && n >= 0 && n < (qint64(1) << 53)) ? n : -1;
    }

    void openDataConnection(int code, const QString &text) {
        bool ok = false;
        const quint16 port = (code == 229) ? parseEpsv(text, &ok) : parsePasv(text, &ok);
        if (!ok || port == 0) { failWith(tr("Could not parse FTP passive-mode reply."), true); return; }

        const QHostAddress peer = m_control->peerAddress();
        if (peer.isNull()) { failWith(tr("FTP passive-mode address rejected for security."), false); return; }

        m_data = new QSslSocket(this);
        // The data socket is dialled by IP (anti-bounce: only the control peer
        // is ever contacted), so TLS verification would otherwise check the cert
        // against the IP literal. Pin it to the real hostname instead.
        m_data->setPeerVerifyName(m_url.host());
        connect(m_data, &QAbstractSocket::connected, this, [this]() {
            if (m_secure) { installSslDiagnostics(m_data); m_data->startClientEncryption(); }
        });
        connect(m_data, &QIODevice::readyRead, this, [this]() { if (!m_manualPump) emit dataReady(); });
        connect(m_data, &QAbstractSocket::errorOccurred, this, [this](QAbstractSocket::SocketError){
            if (m_phase == Phase::Rest || m_phase == Phase::Retr || m_phase == Phase::Transferring)
                failWith(tr("Could not open FTP data connection."), true);
        });
        m_data->connectToHost(peer, port);

        if (m_startOffset > 0) { m_phase = Phase::Rest; send(QStringLiteral("REST %1").arg(m_startOffset)); }
        else                   sendRetr();
    }

    // "229 ... (|||PORT|)" — delimiter is the first char after '(', port is 3rd field.
    quint16 parseEpsv(const QString &text, bool *ok) {
        *ok = false;
        const int lp = text.indexOf(QLatin1Char('('));
        const int rp = text.indexOf(QLatin1Char(')'), lp + 1);
        if (lp < 0 || rp <= lp + 1) return 0;
        const QString inner = text.mid(lp + 1, rp - lp - 1);
        if (inner.isEmpty()) return 0;
        const QStringList parts = inner.split(inner.at(0));
        if (parts.size() < 4) return 0;
        bool pok = false;
        const int p = parts.at(3).toInt(&pok);
        if (!pok || p < 1 || p > 65535) return 0;
        *ok = true; return static_cast<quint16>(p);
    }

    // "227 ...(h1,h2,h3,h4,p1,p2)" — every octet validated 0..255; host ignored
    // for dialling (only the port is used; see openDataConnection).
    quint16 parsePasv(const QString &text, bool *ok) {
        *ok = false;
        static const QRegularExpression re(QStringLiteral("(\\d+),(\\d+),(\\d+),(\\d+),(\\d+),(\\d+)"));
        const QRegularExpressionMatch m = re.match(text);
        if (!m.hasMatch()) return 0;
        int v[6];
        for (int i = 0; i < 6; ++i) {
            bool vok = false; v[i] = m.captured(i + 1).toInt(&vok);
            if (!vok || v[i] < 0 || v[i] > 255) return 0;
        }
        const int port = v[4] * 256 + v[5];
        if (port < 1 || port > 65535) return 0;
        *ok = true; return static_cast<quint16>(port);
    }

    void installSslDiagnostics(QSslSocket *s) {
        // NEVER ignoreSslErrors(): a bad certificate must fail the transfer.
        connect(s, &QSslSocket::sslErrors, this, [this](const QList<QSslError> &errs) {
            QStringList msgs; for (const QSslError &e : errs) msgs << e.errorString();
            failWith(tr("TLS handshake failed: %1").arg(msgs.join(QStringLiteral("; "))), false);
        });
    }

    QString userOrAnon() const { return m_user.isEmpty() ? QStringLiteral("anonymous") : m_user; }
    QString passOrAnon() const { return m_user.isEmpty() ? QStringLiteral("anonymous@") : m_pass; }
    // Server reply text is untrusted and flows into user-visible error strings.
    // Strip control chars and bidi/isolate overrides (terminal/RTL spoofing),
    // collapse whitespace, and cap the length before display.
    static QString sanitizeServerText(QString t) {
        static const QRegularExpression bad(
            QStringLiteral("[\\x00-\\x1f\\x7f\\x{202a}-\\x{202e}\\x{2066}-\\x{2069}]"));
        t.remove(bad);
        return t.simplified().left(200);
    }
    static QString serverMsg(const QString &prefix, const QString &text) {
        const QString t = sanitizeServerText(text);
        return t.isEmpty() ? (prefix + QLatin1Char('.')) : QStringLiteral("%1: %2").arg(prefix, t);
    }
    QString loginError(const QString &text) const { return serverMsg(tr("FTP login failed"), text); }

    void failWith(const QString &reason, bool transient) {
        if (m_phase == Phase::Failed || m_phase == Phase::Done) return;
        m_phase = Phase::Failed; m_timer->stop();
        emit failed(reason, transient);
    }

    QUrl    m_url;
    QString m_user, m_pass;
    bool    m_secure;
    bool    m_wantSize;
    int     m_timeoutMs;
    qint64  m_startOffset{0}, m_endOffset{-1};

    QSslSocket *m_control{nullptr};
    QSslSocket *m_data{nullptr};
    QTimer     *m_timer{nullptr};
    Phase   m_phase{Phase::Connecting};
    bool    m_manualPump{false};

    bool    m_inMultiline{false};
    int     m_mlCode{0}, m_replyCode{0};
    QString m_replyText;

    qint64  m_reportedSize{-1};
    bool    m_restAccepted{false};
};

// ─────────────────────────────────────────────────────────────────────────────
// FtpTransfer
// ─────────────────────────────────────────────────────────────────────────────
FtpTransfer::FtpTransfer(DownloadItem *item, int segments, QObject *parent)
    : Transfer(parent), m_item(item), m_segmentCount(std::clamp(segments, 1, kMaxSegments))
{
    m_progressTimer = new QTimer(this);
    m_progressTimer->setInterval(kTickIntervalMs);
    connect(m_progressTimer, &QTimer::timeout, this, &FtpTransfer::onProgressTick);
}

FtpTransfer::~FtpTransfer() {
    m_progressTimer->stop();
    teardownAll();
}

bool FtpTransfer::isSecure() const {
    return m_item->url().scheme().compare(QStringLiteral("ftps"), Qt::CaseInsensitive) == 0;
}

QString FtpTransfer::remotePath() const {
    const QString p = m_item->url().path();
    return p.isEmpty() ? QStringLiteral("/") : p;
}

QString FtpTransfer::deriveFilename() const {
    QString last = m_item->url().fileName();
    if (last.isEmpty())
        last = m_item->url().path().section(QLatin1Char('/'), -1, -1);
    return sanitizeFilename(last);
}

void FtpTransfer::start() {
    m_paused = m_cancelled = m_failed = false;
    m_item->setLastTryAt(QDateTime::currentDateTime());

    const QString rpath = remotePath();
    if (rpath.contains(QLatin1Char('\r')) || rpath.contains(QLatin1Char('\n'))) {
        failTransfer(tr("Invalid FTP path.")); return;
    }
    if (m_item->filename().isEmpty())
        m_item->setFilename(deriveFilename());

    QDir().mkpath(m_item->savePath());

    // Resume from a previous session if meta + parts survive.
    if (loadMeta() && !m_segments.isEmpty()) {
        bool allDone = true;
        for (const auto &s : m_segments) if (!s.done) { allDone = false; break; }
        if (allDone) { mergeAndFinish(); return; }
        m_item->setStatus(DownloadItem::Status::Downloading);
        m_lastReceived = m_item->doneBytes();
        m_nextSegmentToStart = 0;
        startPendingSegments();
        m_progressTimer->start();
        return;
    }

    m_item->setStatus(DownloadItem::Status::Downloading);
    beginPrimary();
}

void FtpTransfer::beginPrimary() {
    // The primary control connection logs in, runs SIZE, then is reused as the
    // connection for segment 0 (no wasted login). Extra segments get their own
    // connections in startPendingSegments().
    auto *primary = new FtpControl(m_item->url(), m_item->username(), m_item->password(),
                                   isSecure(), /*wantSize*/true, kCommandTimeoutMs, this);

    connect(primary, &FtpControl::failed, this, [this, primary](const QString &reason, bool) {
        if (m_cancelled || m_failed) { primary->deleteLater(); return; }
        primary->deleteLater();
        failTransfer(reason);
    });

    connect(primary, &FtpControl::ready, this, [this, primary](qint64 size) {
        if (m_cancelled || m_failed) return;
        m_controlPeer = primary->controlPeer();
        const bool restProbe = size > 0; // assume REST works; verified on first resume use
        onPrimaryReady(size, restProbe, primary);
    });

    primary->start();
}

void FtpTransfer::onPrimaryReady(qint64 totalBytes, bool restMaybe, FtpControl *primary) {
    const bool known = totalBytes > 0;
    m_resumeCapable = known;            // REST-based resume needs a known length
    if (known) m_item->setTotalBytes(totalBytes);
    m_item->setResumeCapable(m_resumeCapable);

    const bool multi = known && totalBytes >= (kMinSegmentSize * 2) && m_segmentCount > 1;
    m_restSupported  = restMaybe;
    setupSegments(known ? totalBytes : -1, multi);

    // Wire the already-logged-in primary connection to segment 0 and start it.
    Segment &s0 = m_segments[0];
    s0.conn = primary;
    bindSegmentConnection(0);
    if (!openSegmentFile(s0)) return;
    // Stamp the stall clock now: if the server acks RETR but never sends a byte,
    // the Transferring phase exits the control timer, so only the FtpTransfer
    // stall watchdog catches it — and it ignores segments with lastByteTime == 0.
    s0.lastByteTime = QDateTime::currentMSecsSinceEpoch();
    s0.conn->retrieve(s0.startOffset, s0.endOffset);

    // Bring up the remaining segments (each its own fresh connection) lazily.
    m_nextSegmentToStart = 1;
    startPendingSegments();

    m_lastReceived = m_item->doneBytes();
    m_progressTimer->start();
}

void FtpTransfer::setupSegments(qint64 totalBytes, bool multi) {
    m_segments.clear();
    int segCount = 1;
    if (multi && totalBytes > qint64(kMinSegmentSize) * m_segmentCount)
        segCount = m_segmentCount;

    if (totalBytes <= 0 || segCount == 1) {
        Segment seg;
        seg.index = 0; seg.startOffset = 0;
        seg.endOffset = totalBytes > 0 ? totalBytes - 1 : -1;
        seg.partPath = partPath(0); seg.uiSlot = 0;
        m_segments.append(seg);
    } else {
        const qint64 segSize = totalBytes / segCount;
        for (int i = 0; i < segCount; ++i) {
            Segment seg;
            seg.index = i;
            seg.startOffset = i * segSize;
            seg.endOffset   = (i == segCount - 1) ? totalBytes - 1 : (i + 1) * segSize - 1;
            seg.partPath = partPath(i); seg.uiSlot = i;
            m_segments.append(seg);
        }
    }
    updateSegmentDataOnItem();
}

bool FtpTransfer::openSegmentFile(Segment &seg) {
    if (!seg.file) seg.file = new QFile(longPath(seg.partPath));
    if (!seg.file->isOpen()) {
        if (!seg.file->open(QIODevice::ReadWrite)) {
            failTransfer(tr("Cannot open part file: %1").arg(seg.file->errorString()));
            return false;
        }
    }
    // Resume: continue writing past whatever is already on disk.
    seg.received = std::max<qint64>(seg.received, 0);
    seg.file->seek(seg.received);
    return true;
}

// Connect a segment's FtpControl signals to this transfer. The connection must
// already be logged in (Idle); the caller then calls retrieve() on it.
void FtpTransfer::bindSegmentConnection(int index) {
    Segment &seg = m_segments[index];
    FtpControl *c = seg.conn;
    c->setManualDataPump(m_speedLimitKBps > 0);

    connect(c, &FtpControl::dataReady, this, [this, index]() { onSegmentData(index); });
    connect(c, &FtpControl::completed, this, [this, index]() { onSegmentComplete(index); });
    connect(c, &FtpControl::failed, this, [this, index](const QString &reason, bool transient) {
        onSegmentError(index, reason, transient);
    });
}

void FtpTransfer::startSegment(Segment &seg) {
    // A fresh (non-primary) segment: new login, then retrieve its range.
    seg.conn = new FtpControl(m_item->url(), m_item->username(), m_item->password(),
                              isSecure(), /*wantSize*/false, kCommandTimeoutMs, this);
    const int index = seg.index;
    connect(seg.conn, &FtpControl::ready, this, [this, index](qint64) {
        if (m_cancelled || m_failed) return;
        Segment &s = m_segments[index];
        const qint64 resumeFrom = s.startOffset + s.received;
        s.lastByteTime = QDateTime::currentMSecsSinceEpoch(); // arm stall watchdog (see onPrimaryReady)
        s.conn->retrieve(resumeFrom, s.endOffset);
    });
    bindSegmentConnection(index);
    if (!openSegmentFile(seg)) return;
    seg.conn->start();
}

void FtpTransfer::startPendingSegments() {
    for (; m_nextSegmentToStart < m_segments.size(); ++m_nextSegmentToStart) {
        Segment &seg = m_segments[m_nextSegmentToStart];
        if (seg.done) continue;
        if (seg.conn) continue; // segment 0 (primary) already running
        startSegment(seg);
    }
}

// Read available data for one segment in unlimited mode, capped at its range.
void FtpTransfer::onSegmentData(int index) {
    if (index < 0 || index >= m_segments.size()) return;
    Segment &seg = m_segments[index];
    if (seg.done || !seg.conn || !seg.conn->dataSocket() || !seg.file) return;

    QSslSocket *sock = seg.conn->dataSocket();
    qint64 avail = sock->bytesAvailable();
    if (avail <= 0) return;

    // Bound to the segment's remaining range so a hostile server can't overflow
    // a known-length range by streaming extra bytes.
    qint64 cap = avail;
    if (seg.endOffset >= 0) {
        const qint64 remaining = (seg.endOffset - seg.startOffset + 1) - seg.received;
        if (remaining <= 0) { seg.done = true; sock->close(); checkAllDone(); return; }
        cap = std::min(avail, remaining);
    }
    const QByteArray data = sock->read(cap);
    if (data.isEmpty()) return;
    const qint64 w = seg.file->write(data);
    if (w != data.size()) { failTransfer(tr("Disk write failed: %1").arg(seg.file->errorString())); return; }
    seg.received += w;
    seg.lastByteTime = QDateTime::currentMSecsSinceEpoch();

    if (seg.endOffset >= 0 && seg.received >= (seg.endOffset - seg.startOffset + 1)) {
        seg.done = true; sock->close(); checkAllDone();
    }
}

void FtpTransfer::onSegmentComplete(int index) {
    if (index < 0 || index >= m_segments.size()) return;
    Segment &seg = m_segments[index];
    // Drain any final bytes the data socket still holds.
    if (seg.conn && seg.conn->dataSocket() && seg.file) {
        QSslSocket *sock = seg.conn->dataSocket();
        while (sock->bytesAvailable() > 0) {
            qint64 cap = sock->bytesAvailable();
            if (seg.endOffset >= 0) {
                const qint64 remaining = (seg.endOffset - seg.startOffset + 1) - seg.received;
                if (remaining <= 0) break;
                cap = std::min(cap, remaining);
            }
            const QByteArray data = sock->read(cap);
            if (data.isEmpty()) break;
            const qint64 w = seg.file->write(data);
            if (w != data.size()) {
                failTransfer(tr("Disk write failed: %1").arg(seg.file->errorString())); return;
            }
            seg.received += w;
        }
    }

    // Truncation guard: for a known-length range, a 226 with fewer bytes than
    // requested means the server closed early — retry the shortfall.
    if (seg.endOffset >= 0) {
        const qint64 expected = seg.endOffset - seg.startOffset + 1;
        if (seg.received < expected) { onSegmentError(index, tr("FTP transfer was truncated."), true); return; }
    }
    seg.done = true;
    checkAllDone();
}

void FtpTransfer::onSegmentError(int index, const QString &reason, bool transient) {
    if (m_cancelled || m_failed) return;
    if (index < 0 || index >= m_segments.size()) { failTransfer(reason); return; }
    Segment &seg = m_segments[index];

    // A secondary segment that can't even log in / open a data conn usually
    // means the server refuses parallelism — collapse rather than fail.
    const bool isSecondary = (index > 0);
    if (isSecondary && transient && m_segments.size() > 1 && seg.received == 0 && seg.retryCount == 0) {
        collapseToSingleConnection();
        return;
    }

    teardownSegment(seg, /*deleteFile*/false);
    if (transient) retrySegment(index);
    else           failTransfer(reason);
}

// Abandon all but segment 0; extend segment 0 to cover the whole file. Used when
// the server refuses extra connections or REST on a parallel segment.
void FtpTransfer::collapseToSingleConnection() {
    if (m_segments.isEmpty()) return;
    const qint64 total = m_item->totalBytes();

    // Tear down every segment except index 0.
    for (int i = m_segments.size() - 1; i >= 1; --i) {
        teardownSegment(m_segments[i], /*deleteFile*/true);
        m_segments.removeAt(i);
    }
    Segment &s0 = m_segments[0];
    // If segment 0 is still mid-flight, keep it; otherwise restart it for the
    // full range. Either way it now owns [0, total-1].
    s0.endOffset = total > 0 ? total - 1 : -1;
    m_restSupported = false;
    m_resumeCapable = false;
    m_item->setResumeCapable(false);
    m_nextSegmentToStart = m_segments.size(); // nothing left to bring up
    updateSegmentDataOnItem();

    if (!s0.conn) {
        s0.received = 0;
        if (s0.file) { s0.file->resize(0); s0.file->seek(0); }
        startSegment(s0);
    }
}

void FtpTransfer::checkAllDone() {
    for (const auto &s : m_segments) if (!s.done) return;
    m_progressTimer->stop();
    mergeAndFinish();
}

void FtpTransfer::onProgressTick() {
    if (!m_item) return;

    // Throttled mode: pull at most one tick's byte budget, fair-shared across
    // active segments (mirrors SegmentedTransfer's two-pass distribution).
    if (m_speedLimitKBps > 0) {
        qint64 budget = qint64(m_speedLimitKBps) * 1024 * kTickIntervalMs / 1000;
        int busy = 0;
        for (const auto &s : m_segments) if (!s.done) ++busy;
        if (busy > 0) {
            const qint64 share = std::max<qint64>(1, budget / busy);
            auto pump = [&](Segment &seg, qint64 cap) {
                if (seg.done || !seg.conn || !seg.conn->dataSocket() || !seg.file || cap <= 0) return;
                QSslSocket *sock = seg.conn->dataSocket();
                qint64 want = std::min(sock->bytesAvailable(), cap);
                if (seg.endOffset >= 0)
                    want = std::min(want, (seg.endOffset - seg.startOffset + 1) - seg.received);
                if (want <= 0) return;
                const QByteArray data = sock->read(want);
                if (data.isEmpty()) return;
                if (seg.file->write(data) != data.size()) {
                    failTransfer(tr("Disk write failed: %1").arg(seg.file->errorString())); return;
                }
                seg.received += data.size();
                seg.lastByteTime = QDateTime::currentMSecsSinceEpoch();
                budget -= data.size();
            };
            for (auto &seg : m_segments) pump(seg, std::min(share, budget));
            for (auto &seg : m_segments) pump(seg, budget); // redistribute leftover
            for (auto &seg : m_segments) {
                if (!seg.done && seg.endOffset >= 0 &&
                    seg.received >= (seg.endOffset - seg.startOffset + 1)) {
                    seg.done = true;
                    if (seg.conn && seg.conn->dataSocket()) seg.conn->dataSocket()->close();
                }
            }
            bool allDone = true;
            for (const auto &s : m_segments) if (!s.done) { allDone = false; break; }
            if (allDone) { m_progressTimer->stop(); mergeAndFinish(); return; }
        }
    }

    // Unknown-length guard: a server that never sent SIZE could stream forever.
    // Once such a segment crosses the ceiling, fail rather than fill the disk.
    for (const auto &seg : m_segments) {
        if (seg.endOffset < 0 && seg.received > kMaxUnknownLengthBytes) {
            failTransfer(tr("FTP transfer exceeded the maximum size for an "
                            "unknown-length download (%1 GB).")
                         .arg(kMaxUnknownLengthBytes / (1024 * 1024 * 1024)));
            return;
        }
    }

    // Stall detection: a segment that received bytes but has gone silent past
    // the timeout is retried.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (int i = 0; i < m_segments.size(); ++i) {
        auto &seg = m_segments[i];
        if (seg.done || !seg.conn || seg.lastByteTime == 0) continue;
        if (now - seg.lastByteTime > kStallTimeoutMs) {
            teardownSegment(seg, false);
            retrySegment(i);
        }
    }

    qint64 totalReceived = 0;
    for (const auto &s : m_segments) totalReceived += s.received;
    m_item->setDoneBytes(totalReceived);

    const qint64 delta = totalReceived - m_lastReceived;
    m_lastReceived = totalReceived;
    m_speedSamples.append(delta);
    if (m_speedSamples.size() > kSpeedWindowTicks) m_speedSamples.removeFirst();

    static constexpr int kTicksPerSecond = 1000 / kTickIntervalMs;
    const int displayN = std::min<int>(m_speedSamples.size(), kDisplayWindowTicks);
    qint64 displaySum = 0;
    for (int i = m_speedSamples.size() - displayN; i < m_speedSamples.size(); ++i) displaySum += m_speedSamples[i];
    const qint64 speedBps = displayN > 0 ? (displaySum * kTicksPerSecond / displayN) : 0;
    m_item->setSpeed(speedBps);
    {
        qint64 sum = 0; for (qint64 s : m_speedSamples) sum += s;
        m_item->setEtaSpeed(!m_speedSamples.isEmpty() ? (sum * kTicksPerSecond / m_speedSamples.size()) : 0);
    }

    if (delta > 0) updateSegmentDataOnItem();

    if (++m_ticksSinceMetaSave >= kMetaSaveIntervalTicks) { m_ticksSinceMetaSave = 0; saveMeta(); }
    emit progressChanged(totalReceived, m_item->totalBytes(), speedBps);
}

void FtpTransfer::retrySegment(int index, int extraDelayMs) {
    if (m_cancelled || m_paused || index < 0 || index >= m_segments.size()) return;
    Segment &seg = m_segments[index];
    if (seg.retryCount >= kMaxSegmentRetries) {
        failTransfer(tr("FTP segment %1 failed after %2 retries.").arg(index + 1).arg(kMaxSegmentRetries));
        return;
    }
    const int delayMs = 1000 * (1 << seg.retryCount) + extraDelayMs;
    ++seg.retryCount;
    QTimer::singleShot(delayMs, this, [this, index]() {
        if (m_cancelled || m_paused || index < 0 || index >= m_segments.size()) return;
        Segment &s = m_segments[index];
        if (s.done || s.conn) return;
        startSegment(s);
    });
}

void FtpTransfer::mergeAndFinish() {
    const QString saveDir = m_item->savePath();
    QFileInfo dirInfo(saveDir);
    if (!dirInfo.isDir()) { QDir().mkpath(saveDir); dirInfo.refresh(); }
    if (!dirInfo.isWritable()) {
        failTransfer(tr("No write permission for download directory: %1").arg(saveDir));
        return;
    }

    // Close all part files before assembly.
    for (auto &seg : m_segments) if (seg.file && seg.file->isOpen()) seg.file->close();

    m_item->setStatus(DownloadItem::Status::Assembling);
    const qint64 total = m_item->totalBytes();
    m_item->setDoneBytes(0);
    m_speedSamples.clear();
    m_item->setSpeed(0);
    m_item->setEtaSpeed(0);

    const QString outPath = longPath(m_item->savePath() + QStringLiteral("/") + m_item->filename());

    struct PartInfo { QString path; qint64 startOffset; qint64 expectedLen; };
    QList<PartInfo> parts;
    const bool singleNoRange = (m_segments.size() == 1 && m_segments[0].endOffset < 0);
    if (singleNoRange) {
        parts.append({ m_segments[0].partPath, 0, -1 });
    } else {
        for (const auto &seg : m_segments)
            parts.append({ seg.partPath, seg.startOffset,
                           seg.endOffset >= 0 ? seg.endOffset - seg.startOffset + 1 : -1 });
        std::sort(parts.begin(), parts.end(),
                  [](const PartInfo &a, const PartInfo &b){ return a.startOffset < b.startOffset; });
    }

    auto *watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcher<QString>::finished, this, [this, watcher]() {
        watcher->deleteLater();
        const QString err = watcher->result();
        if (!err.isEmpty()) { failTransfer(err); return; }
        cleanupPartFiles();
        deleteMetaFile();
        m_item->setStatus(DownloadItem::Status::Completed);
        emit finished();
    });

    // QPointer guard: a large merge can outlive the download if the user deletes
    // it mid-assembly, freeing the DownloadItem. Gate the worker deref and the
    // queued invoke's receiver on the pointer still being valid.
    QPointer<DownloadItem> itemPtr = m_item;
    watcher->setFuture(QtConcurrent::run([singleNoRange, parts, outPath, itemPtr, total]() -> QString {
        auto report = [&](qint64 written) {
            DownloadItem *item = itemPtr.data();
            if (!item) return;
            QMetaObject::invokeMethod(item, [item, written]() { item->setDoneBytes(written); },
                                      Qt::QueuedConnection);
        };
        if (singleNoRange) {
            const QString &src = parts[0].path;
            if (QFile::rename(src, outPath)) { report(QFileInfo(outPath).size()); return {}; }
            QFile s(src);
            if (!s.open(QIODevice::ReadOnly))
                return QStringLiteral("Cannot open part file: %1 (%2)").arg(src, s.errorString());
            QFile d(outPath);
            if (!d.open(QIODevice::ReadWrite | QIODevice::Truncate))
                return QStringLiteral("Cannot create output file: %1 (%2)").arg(outPath, d.errorString());
            const qint64 sz = s.size(); d.resize(sz);
            QString e; if (!mappedRangeCopy(s, 0, sz, d, 0, &e)) { d.close(); QFile::remove(outPath); return e; }
            report(sz); d.close(); QFile::remove(src); return {};
        }

        QFile out(outPath);
        if (!out.open(QIODevice::ReadWrite | QIODevice::Truncate))
            return QStringLiteral("Cannot create output file: %1 (%2)").arg(outPath, out.errorString());
        if (total > 0 && !out.resize(total))
            return QStringLiteral("Cannot pre-allocate output file: %1 (%2)").arg(outPath, out.errorString());

        qint64 written = 0;
        for (const auto &part : parts) {
            QFile pf(part.path);
            if (!pf.open(QIODevice::ReadOnly)) {
                out.close(); QFile::remove(outPath);
                return QStringLiteral("Cannot open part file: %1 (%2)").arg(part.path, pf.errorString());
            }
            const qint64 sz = pf.size();
            // A part larger than its declared range would copy into the next
            // segment's bytes and push the output past its true length. Reject
            // any mismatch rather than assemble a corrupt file.
            if (part.expectedLen >= 0 && sz != part.expectedLen) {
                pf.close(); out.close(); QFile::remove(outPath);
                return QStringLiteral("Part file size mismatch: %1 (expected %2, got %3)")
                    .arg(part.path).arg(part.expectedLen).arg(sz);
            }
            qint64 off = 0, outOff = part.startOffset, remaining = sz;
            while (remaining > 0) {
                const qint64 window = std::min(remaining, kFtpMapWindow);
                QString e;
                if (!mappedRangeCopy(pf, off, window, out, outOff, &e)) {
                    pf.close(); out.close(); QFile::remove(outPath); return e;
                }
                off += window; outOff += window; remaining -= window; written += window;
                report(written);
            }
            pf.close();
        }
        out.close();
        if (out.error() != QFileDevice::NoError)
            return QStringLiteral("Output file error after assembly: %1").arg(out.errorString());
        return {};
    }));
}

void FtpTransfer::pause() {
    if (m_paused || !m_item) return;
    m_paused = true;
    m_progressTimer->stop();
    for (auto &seg : m_segments) teardownSegment(seg, /*deleteFile*/false);
    saveMeta();
    m_speedSamples.clear();
    m_item->setStatus(DownloadItem::Status::Paused);
    m_item->setSpeed(0);
    m_item->setEtaSpeed(0);
}

void FtpTransfer::resume() {
    if (!m_paused) return;
    m_paused = false;

    bool allDone = true;
    for (const auto &s : m_segments) if (!s.done) { allDone = false; break; }
    if (allDone) { mergeAndFinish(); return; }

    m_item->setStatus(DownloadItem::Status::Downloading);
    m_lastReceived = m_item->doneBytes();
    m_nextSegmentToStart = 0;
    startPendingSegments();
    m_progressTimer->start();
}

void FtpTransfer::abort() {
    m_cancelled = true;
    m_progressTimer->stop();
    teardownAll();
    m_speedSamples.clear();
    cleanupPartFiles();
    deleteMetaFile();
    // Do not touch m_item — DownloadQueue::cancel() owns its final state.
}

bool FtpTransfer::relocateOutput(const QString &newSavePath, const QString &newFilename) {
    if (!m_item) return false;
    const QString oldMeta = metaPath();
    if (m_item->savePath() == newSavePath && m_item->filename() == newFilename) return true;

    QDir().mkpath(newSavePath);
    for (auto &seg : m_segments) {
        const QString newPart = longPath(newSavePath + QStringLiteral("/") + m_item->id()
            + QStringLiteral(".stellar-part-") + QString::number(seg.index));
        if (seg.partPath == newPart) continue;
        const bool wasOpen = seg.file && seg.file->isOpen();
        if (wasOpen) seg.file->close();
        if (QFile::exists(seg.partPath) && !QFile::rename(seg.partPath, newPart)) {
            if (wasOpen && seg.file) seg.file->open(QIODevice::ReadWrite);
            return false;
        }
        if (seg.file) seg.file->setFileName(newPart);
        if (wasOpen && seg.file) {
            if (!seg.file->open(QIODevice::ReadWrite)) return false;
            if (seg.received > 0) seg.file->seek(seg.received);
        }
        seg.partPath = newPart;
    }
    m_item->setSavePath(newSavePath);
    m_item->setFilename(newFilename);
    if (QFile::exists(oldMeta)) QFile::rename(oldMeta, metaPath());
    saveMeta();
    return true;
}

void FtpTransfer::setSpeedLimitKBps(int kbps) {
    m_speedLimitKBps = kbps;
    // Switch every live segment between manual-pump (throttled) and readyRead.
    for (auto &seg : m_segments)
        if (seg.conn) seg.conn->setManualDataPump(kbps > 0);
}

void FtpTransfer::setTemporaryDirectory(const QString &path) { m_temporaryDirectory = path; }
void FtpTransfer::setMaxConnectionsPerHost(int v) { m_maxConnectionsPerHost = v; }

void FtpTransfer::failTransfer(const QString &reason) {
    if (m_failed) return;
    m_failed = true;
    m_progressTimer->stop();
    teardownAll();
    if (m_item) m_item->setStatus(DownloadItem::Status::Error);
    emit failed(reason);
}

void FtpTransfer::teardownSegment(Segment &seg, bool deleteFile) {
    if (seg.conn) { seg.conn->disconnect(this); seg.conn->deleteLater(); seg.conn = nullptr; }
    if (seg.file) {
        seg.file->close();
        if (deleteFile) seg.file->remove();
        delete seg.file; seg.file = nullptr;
    }
    seg.lastByteTime = 0;
}

void FtpTransfer::teardownAll() {
    for (auto &seg : m_segments) {
        if (seg.conn) { seg.conn->disconnect(this); seg.conn->deleteLater(); seg.conn = nullptr; }
        if (seg.file) { seg.file->close(); delete seg.file; seg.file = nullptr; }
    }
}

// ── Persistence ──────────────────────────────────────────────────────────────
QString FtpTransfer::tempBaseDirectory() const {
    return m_temporaryDirectory.trimmed().isEmpty() ? m_item->savePath() : m_temporaryDirectory.trimmed();
}
QString FtpTransfer::metaPath() const {
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->id() + QStringLiteral(".stellar-meta"));
}
QString FtpTransfer::partPath(int index) const {
    return longPath(tempBaseDirectory() + QStringLiteral("/") + m_item->id()
           + QStringLiteral(".stellar-part-") + QString::number(index));
}
void FtpTransfer::deleteMetaFile() { QFile::remove(metaPath()); }
void FtpTransfer::cleanupPartFiles() {
    for (const auto &seg : m_segments) QFile::remove(seg.partPath);
    QDir d(tempBaseDirectory());
    const QStringList filters = { m_item->id() + QStringLiteral(".stellar-part-*") };
    for (const QFileInfo &fi : d.entryInfoList(filters, QDir::Files | QDir::NoDotAndDotDot))
        QFile::remove(fi.absoluteFilePath());
}

bool FtpTransfer::saveMeta() {
    QJsonObject root;
    root[QStringLiteral("scheme")]        = QStringLiteral("ftp");
    root[QStringLiteral("url")]           = QString::fromUtf8(m_item->url().toEncoded());
    root[QStringLiteral("totalBytes")]    = m_item->totalBytes();
    root[QStringLiteral("resumeCapable")] = m_resumeCapable;
    QJsonArray segs;
    for (const auto &seg : m_segments) {
        QJsonObject s;
        s[QStringLiteral("startOffset")] = seg.startOffset;
        s[QStringLiteral("endOffset")]   = seg.endOffset;
        s[QStringLiteral("received")]    = seg.received;
        s[QStringLiteral("done")]        = seg.done;
        segs.append(s);
    }
    root[QStringLiteral("segments")] = segs;

    QDir().mkpath(tempBaseDirectory());
    QSaveFile f(metaPath());
    if (!f.open(QIODevice::WriteOnly)) return false;
    if (f.write(QJsonDocument(root).toJson(QJsonDocument::Compact)) < 0) return false;
    return f.commit();
}

bool FtpTransfer::loadMeta() {
    QFile f(metaPath());
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) return false;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (doc.isNull()) return false;
    const QJsonObject root = doc.object();
    if (root[QStringLiteral("scheme")].toString() != QStringLiteral("ftp")) return false;

    const QString metaUrl = root[QStringLiteral("url")].toString();
    if (!metaUrl.isEmpty() && metaUrl != QString::fromUtf8(m_item->url().toEncoded())) return false;

    const qint64 total = root[QStringLiteral("totalBytes")].toVariant().toLongLong();
    if (total <= 0) return false;            // resume needs a known length
    m_item->setTotalBytes(total);
    m_resumeCapable = root[QStringLiteral("resumeCapable")].toBool();
    m_item->setResumeCapable(m_resumeCapable);
    m_restSupported = true;

    const QJsonArray segs = root[QStringLiteral("segments")].toArray();
    if (segs.isEmpty() || segs.size() > kMaxSegments) return false;

    m_segments.clear();
    qint64 done = 0;
    for (int i = 0; i < segs.size(); ++i) {
        const QJsonObject s = segs[i].toObject();
        Segment seg;
        seg.index = i;
        seg.startOffset = s[QStringLiteral("startOffset")].toVariant().toLongLong();
        seg.endOffset   = s[QStringLiteral("endOffset")].toVariant().toLongLong();
        seg.partPath = partPath(i);
        seg.uiSlot = i;
        if (seg.startOffset < 0) return false;
        if (seg.endOffset >= 0 && seg.endOffset < seg.startOffset) return false;
        const qint64 expected = seg.endOffset >= 0 ? (seg.endOffset - seg.startOffset + 1) : total;
        if (expected < 0) return false;
        const QFileInfo pi(seg.partPath);
        const qint64 actual = pi.exists() ? pi.size() : 0;
        seg.received = std::clamp<qint64>(actual, 0, expected);
        seg.done = (seg.received >= expected && expected > 0);
        done += seg.received;
        m_segments.append(seg);
    }

    // The meta file lives in a user/process-writable directory; a corrupt or
    // crafted one must not yield overlapping ranges (parts clobber each other in
    // merge), gaps (zero-filled holes), or an out-of-bounds endOffset — any of
    // which produce a silently corrupt file reported as complete. Require the
    // segments to tile [0, total-1] contiguously, in order, with no overlap.
    qint64 expectStart = 0;
    for (const auto &seg : m_segments) {
        if (seg.startOffset != expectStart) return false;     // gap or overlap
        if (seg.endOffset < seg.startOffset) return false;    // empty/inverted
        if (seg.endOffset >= total) return false;             // past EOF
        expectStart = seg.endOffset + 1;
    }
    if (expectStart != total) return false;                   // incomplete coverage

    m_item->setDoneBytes(done);
    updateSegmentDataOnItem();
    return true;
}

void FtpTransfer::updateSegmentDataOnItem() {
    int slotCount = std::max(1, m_segmentCount);
    for (const auto &seg : m_segments)
        if (seg.uiSlot >= 0) slotCount = std::max(slotCount, seg.uiSlot + 1);

    QVariantList list;
    list.reserve(slotCount);
    for (int i = 0; i < slotCount; ++i) {
        QVariantMap m;
        m[QStringLiteral("startByte")] = qint64(0);
        m[QStringLiteral("endByte")]   = qint64(-1);
        m[QStringLiteral("received")]  = qint64(0);
        m[QStringLiteral("info")]      = QStringLiteral("Waiting...");
        list.append(m);
    }
    for (const auto &seg : m_segments) {
        if (seg.uiSlot < 0 || seg.uiSlot >= slotCount) continue;
        QVariantMap m;
        m[QStringLiteral("startByte")] = seg.startOffset;
        m[QStringLiteral("endByte")]   = seg.endOffset;
        m[QStringLiteral("received")]  = seg.received;
        m[QStringLiteral("info")]      = seg.done ? QStringLiteral("Complete")
                                        : (seg.conn ? QStringLiteral("Receiving data...")
                                                    : QStringLiteral("Waiting..."));
        list[seg.uiSlot] = m;
    }
    m_item->setSegmentData(list);
}

#include "FtpTransfer.moc"
