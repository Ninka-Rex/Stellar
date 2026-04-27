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

#include "SystemTrayIcon.h"
#include <QIcon>
#include <QPixmap>
#include <QPainter>
#include <QFont>
#include <QCursor>
#include <QCoreApplication>
#include <QProcess>
#include <QStandardPaths>

#if defined(STELLAR_WINDOWS)
#  include <windows.h>
#endif

static QIcon createDefaultIcon() {
    QPixmap pm(16, 16);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setBrush(QColor(0x44, 0x88, 0xdd));
    p.setPen(Qt::NoPen);
    p.drawEllipse(1, 1, 14, 14);
    p.setPen(Qt::white);
    QFont f = p.font();
    f.setPixelSize(10);
    f.setBold(true);
    p.setFont(f);
    p.drawText(QRect(1, 1, 14, 14), Qt::AlignCenter, QStringLiteral("S"));
    p.end();
    return QIcon(pm);
}

static QString psQuoted(const QString &value)
{
    QString escaped = value;
    escaped.replace(QLatin1Char('\''), QStringLiteral("''"));
    escaped.replace(QLatin1Char('\r'), QStringLiteral(" "));
    escaped.replace(QLatin1Char('\n'), QStringLiteral(" "));
    return QStringLiteral("'") + escaped + QStringLiteral("'");
}

static QIcon createDownloadsTrayIcon() {
    const QIcon icon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/arrow_down.png"));
    if (!icon.isNull())
        return icon;
    // Fallback: simple down-arrow drawn pixmap
    QPixmap pm(16, 16);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setBrush(QColor(0x44, 0x88, 0xdd));
    p.setPen(Qt::NoPen);
    // Arrow shape: triangle pointing down
    QPolygon arrow;
    arrow << QPoint(2, 5) << QPoint(14, 5) << QPoint(8, 13);
    p.drawPolygon(arrow);
    p.end();
    return QIcon(pm);
}

SystemTrayIcon::SystemTrayIcon(QObject *parent)
    : QObject(parent)
{
    m_tray = new QSystemTrayIcon(this);
    const QIcon appIcon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/milky-way.ico"));
    m_tray->setIcon(appIcon.isNull() ? createDefaultIcon() : appIcon);
    m_tray->setToolTip(QStringLiteral("Stellar Download Manager"));

    connect(m_tray, &QSystemTrayIcon::activated, this,
            [this](QSystemTrayIcon::ActivationReason reason) {
        switch (reason) {
        case QSystemTrayIcon::DoubleClick:
            emit showRequested();
            break;
        case QSystemTrayIcon::Trigger:
            emit showRequested();
            break;
        case QSystemTrayIcon::Context: {
            const QPoint pos = QCursor::pos();
            emit contextMenuRequested(pos.x(), pos.y());
            break;
        }
        default:
            break;
        }
    });

    // Downloads tray icon
    m_downloadsTray = new QSystemTrayIcon(this);
    m_downloadsTray->setIcon(createDownloadsTrayIcon());
    m_downloadsTray->setToolTip(QStringLiteral("SDM downloads"));

    connect(m_downloadsTray, &QSystemTrayIcon::activated, this,
            [this](QSystemTrayIcon::ActivationReason reason) {
        switch (reason) {
        case QSystemTrayIcon::DoubleClick:
        case QSystemTrayIcon::Trigger:
            emit downloadsShowAllRequested();
            break;
        case QSystemTrayIcon::Context: {
            const QPoint pos = QCursor::pos();
            emit downloadsContextMenuRequested(pos.x(), pos.y());
            break;
        }
        default:
            break;
        }
    });
}

void SystemTrayIcon::setup(const QString &iconPath) {
    m_tray->setIcon(iconPath.isEmpty() ? createDefaultIcon() : QIcon(iconPath));
}

void SystemTrayIcon::show()  { m_tray->show(); }
void SystemTrayIcon::hide()  { m_tray->hide(); }

void SystemTrayIcon::showDownloadsTray()  { m_downloadsTray->show(); }
void SystemTrayIcon::hideDownloadsTray()  { m_downloadsTray->hide(); }
void SystemTrayIcon::setDownloadsTrayToolTip(const QString &tip) { m_downloadsTray->setToolTip(tip); }

void SystemTrayIcon::setToolTip(const QString &tip) {
    m_tray->setToolTip(tip);
}

void SystemTrayIcon::showNotification(const QString &title, const QString &msg) {
    const QString safeTitle = title.trimmed().isEmpty()
        ? QStringLiteral("Stellar Download Manager")
        : title.trimmed();
    const QString safeMsg = msg.trimmed();

#if defined(STELLAR_WINDOWS)
    const QString script = QStringLiteral(
        "Add-Type -AssemblyName System.Windows.Forms; "
        "Add-Type -AssemblyName System.Drawing; "
        "$n = New-Object System.Windows.Forms.NotifyIcon; "
        "$n.Icon = [System.Drawing.SystemIcons]::Information; "
        "$n.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info; "
        "$n.BalloonTipTitle = %1; "
        "$n.BalloonTipText = %2; "
        "$n.Visible = $true; "
        "$n.ShowBalloonTip(4000); "
        "Start-Sleep -Milliseconds 4500; "
        "$n.Dispose();")
        .arg(psQuoted(safeTitle), psQuoted(safeMsg));
    QProcess::startDetached(QStringLiteral("powershell"), {
        QStringLiteral("-NoProfile"),
        QStringLiteral("-NonInteractive"),
        QStringLiteral("-WindowStyle"), QStringLiteral("Hidden"),
        QStringLiteral("-Command"), script
    });
#elif defined(STELLAR_LINUX)
    const QString notifySend = QStandardPaths::findExecutable(QStringLiteral("notify-send"));
    if (!notifySend.isEmpty()) {
        QProcess::startDetached(notifySend, {
            QStringLiteral("--app-name=Stellar"),
            safeTitle,
            safeMsg
        });
    } else {
        const QString kdialog = QStandardPaths::findExecutable(QStringLiteral("kdialog"));
        if (!kdialog.isEmpty()) {
            QProcess::startDetached(kdialog, {
                QStringLiteral("--title"), safeTitle,
                QStringLiteral("--passivepopup"), safeMsg,
                QStringLiteral("4")
            });
        } else {
            const QString zenity = QStandardPaths::findExecutable(QStringLiteral("zenity"));
            if (!zenity.isEmpty()) {
                QProcess::startDetached(zenity, {
                    QStringLiteral("--notification"),
                    QStringLiteral("--text=%1").arg(QStringLiteral("%1\n%2").arg(safeTitle, safeMsg))
                });
            }
        }
    }
#else
    Q_UNUSED(safeTitle);
    Q_UNUSED(safeMsg);
#endif
}
