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

#include "NativeMessagingHost.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDataStream>
#include <QFile>
#ifdef Q_OS_WIN
#  include <io.h>
#  include <fcntl.h>
#else
#  include <unistd.h>
#endif

// Chrome and Firefox both cap native messages at 1 MB.
// Enforced in readMessage() before any buffer allocation.
static constexpr quint32 kMaxNativeMessageSize = 1024u * 1024u;

NativeMessagingHost::NativeMessagingHost(QObject *parent) : QObject(parent) {}

void NativeMessagingHost::start() {
#ifdef Q_OS_WIN
    // Switch stdin/stdout to binary mode so the 4-byte length header is not
    // mangled by CR/LF translation on Windows.
    _setmode(_fileno(stdin),  _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    const int stdinFd = _fileno(stdin);
#else
    const int stdinFd = STDIN_FILENO;
#endif
    m_stdinNotifier = new QSocketNotifier(stdinFd, QSocketNotifier::Read, this);
    connect(m_stdinNotifier, &QSocketNotifier::activated, this, &NativeMessagingHost::readMessage);
}

void NativeMessagingHost::readMessage() {
    // Temporarily disable the notifier while we do blocking reads so it
    // doesn't re-fire before we've consumed the current message.
    m_stdinNotifier->setEnabled(false);

    quint32 len = 0;
    QFile in;
    in.open(stdin, QIODevice::ReadOnly);

    if (in.read(reinterpret_cast<char *>(&len), 4) != 4) {
        // stdin closed — browser exited; stop the event loop gracefully.
        m_stdinNotifier->setEnabled(false);
        return;
    }

    // SECURITY: CWE-789 — Chrome and Firefox cap native messages at 1 MB.
    // Reject oversized lengths before allocating to prevent a 4 GB allocation
    // from a malicious or misbehaving caller.
    if (len == 0 || len > kMaxNativeMessageSize) {
        m_stdinNotifier->setEnabled(false);
        return;
    }

    QByteArray json(static_cast<int>(len), Qt::Uninitialized);
    if (in.read(json.data(), len) != static_cast<qint64>(len)) {
        m_stdinNotifier->setEnabled(false);
        return;
    }

    m_stdinNotifier->setEnabled(true);
    handleMessage(json);
}

void NativeMessagingHost::handleMessage(const QByteArray &json) {
    QJsonDocument doc = QJsonDocument::fromJson(json);
    if (doc.isNull()) return;
    QJsonObject obj = doc.object();
    const QString type = obj[QStringLiteral("type")].toString();

    if (type == QStringLiteral("ping")) {
        emit pingReceived();
        sendReady();
    } else if (type == QStringLiteral("download")) {
        int modifierKey = obj[QStringLiteral("modifierKey")].toInt(0);
        emit downloadRequested(
            obj[QStringLiteral("url")].toString(),
            obj[QStringLiteral("filename")].toString(),
            obj[QStringLiteral("referrer")].toString(),
            obj[QStringLiteral("cookies")].toString(),
            modifierKey
        );
    }
}

void NativeMessagingHost::writeMessage(const QByteArray &json) {
    quint32 len = static_cast<quint32>(json.size());
    // Native Messaging uses native byte order (little-endian on x86)
    QFile out;
    out.open(stdout, QIODevice::WriteOnly);
    out.write(reinterpret_cast<const char *>(&len), 4);
    out.write(json);
    out.flush();
}

void NativeMessagingHost::sendReady() {
    writeMessage(QJsonDocument(QJsonObject{{QStringLiteral("type"), QStringLiteral("ready")}}).toJson(QJsonDocument::Compact));
}

void NativeMessagingHost::sendAck(const QString &downloadId) {
    writeMessage(QJsonDocument(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("ack")},
        {QStringLiteral("id"),   downloadId}
    }).toJson(QJsonDocument::Compact));
}

void NativeMessagingHost::sendError(const QString &message) {
    writeMessage(QJsonDocument(QJsonObject{
        {QStringLiteral("type"),    QStringLiteral("error")},
        {QStringLiteral("message"), message}
    }).toJson(QJsonDocument::Compact));
}
