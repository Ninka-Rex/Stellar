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

NativeMessagingHost::NativeMessagingHost(QObject *parent) : QObject(parent) {}

void NativeMessagingHost::start() {
    // Phase 3: attach QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read)
    // and connect its activated() to readMessage()
}

void NativeMessagingHost::readMessage() {
    // Phase 3:
    // 1. Read 4-byte little-endian length from stdin
    // 2. Read that many bytes as UTF-8 JSON
    // 3. Call handleMessage()
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
