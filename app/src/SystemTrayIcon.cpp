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
}

void SystemTrayIcon::setup(const QString &iconPath) {
    m_tray->setIcon(iconPath.isEmpty() ? createDefaultIcon() : QIcon(iconPath));
}

void SystemTrayIcon::show()  { m_tray->show(); }
void SystemTrayIcon::hide()  { m_tray->hide(); }

void SystemTrayIcon::setToolTip(const QString &tip) {
    m_tray->setToolTip(tip);
}

void SystemTrayIcon::showNotification(const QString &title, const QString &msg) {
    if (qApp && qApp->inherits("QApplication")) {
        m_tray->showMessage(title, msg, QSystemTrayIcon::Information, 3000);
    }
}
