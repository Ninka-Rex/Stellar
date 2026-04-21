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
#include <QByteArray>
#include <QSocketNotifier>

// NativeMessagingHost implements the Chrome/Firefox Native Messaging protocol.
// It reads length-prefixed JSON messages from stdin and writes responses to stdout.
// Run as a subprocess by the browser extension when the user clicks "Download with Stellar".
//
// Protocol: see protocol/native-messaging-schema.json
class NativeMessagingHost : public QObject {
    Q_OBJECT

public:
    explicit NativeMessagingHost(QObject *parent = nullptr);

    // Call once to start reading from stdin (non-blocking via QSocketNotifier)
    void start();

signals:
    void downloadRequested(const QString &url, const QString &filename,
                           const QString &referrer, const QString &cookies,
                           int modifierKey = 0);
    void pingReceived();

public slots:
    void sendReady();
    void sendAck(const QString &downloadId);
    void sendError(const QString &message);

private slots:
    void readMessage();

private:
    void writeMessage(const QByteArray &json);
    void handleMessage(const QByteArray &json);

    QSocketNotifier *m_stdinNotifier{nullptr};
};
