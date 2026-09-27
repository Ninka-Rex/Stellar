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
#include <QImage>
#include <QPixmap>
#include <QPainter>
#include <QFont>
#include <QCursor>
#include <QCoreApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QGuiApplication>

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
    const QIcon icon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/actions/go-down.svg"));
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

static QIcon trayIconForStyle(int style) {
#if defined(Q_OS_LINUX)
    // Linux panels scale the pixmap to fill the whole tray slot, so the
    // edge-to-edge app icon looks oversized next to other tray icons. The
    // app/tray/ set is padded to the usual template geometry (frame inset 2px,
    // ~3.3px corner radius at 22px) and comes in 1x/2x/3x so the panel
    // downsamples from a close size.
    QString base;
    switch (style) {
    case 1:  base = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/tray/stellar-tray-white"); break;
    case 2:  base = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/tray/stellar-tray-black"); break;
    default: base = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/tray/stellar-tray");       break;
    }
    QIcon icon;
    icon.addFile(base + QStringLiteral(".png"),    QSize(22, 22));
    icon.addFile(base + QStringLiteral("@2x.png"), QSize(44, 44));
    icon.addFile(base + QStringLiteral("@3x.png"), QSize(66, 66));
#else
    QString path;
    switch (style) {
    case 1:  path = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/stellar-mono-white.png"); break;
    case 2:  path = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/stellar-mono-black.png"); break;
    default: path = QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/app/stellar.png");       break;
    }
    const QIcon icon(path);
#endif
    return icon.isNull() ? createDefaultIcon() : icon;
}

SystemTrayIcon::SystemTrayIcon(QObject *parent)
    : QObject(parent)
{
    // No parent — tray icon must outlive the Qt object tree so it
    // stays visible until the process fully exits. Windows cleans up
    // notification icons automatically when the owning process terminates.
    m_tray = new QSystemTrayIcon();
    m_tray->setIcon(trayIconForStyle(0));
    m_tray->setToolTip(tr("Stellar Download Manager"));

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

    // Downloads tray icon (no parent — same reason as m_tray)
    m_downloadsTray = new QSystemTrayIcon();
    m_downloadsTray->setIcon(createDownloadsTrayIcon());
    m_downloadsTray->setToolTip(tr("SDM downloads"));

#if defined(Q_OS_LINUX)
    // On KDE/Wayland the Context activation signal never fires — KDE intercepts
    // right-click and shows the native QMenu directly. Set one up so it works.
    m_menu = new QMenu();
    m_menu->setStyleSheet(
        "QMenu { background:#2b2b2b; border:1px solid #555; color:#e0e0e0; }"
        "QMenu::item { padding:4px 20px; }"
        "QMenu::item:selected { background:#3a3a5a; }"
        "QMenu::separator { height:1px; background:#444; margin:2px 0; }"
    );

    auto trayIcon = [](const char *name) {
        return QIcon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/") + QLatin1String(name));
    };

    auto *openAction = m_menu->addAction(tr("Open Stellar"));
    openAction->setFont([&]{ QFont f; f.setBold(true); return f; }());
    connect(openAction, &QAction::triggered, this, &SystemTrayIcon::showRequested);

    m_menu->addAction(trayIcon("actions/list-add-symbolic.svg"), tr("Add URL…"), this, &SystemTrayIcon::addUrlRequested);
    m_stopAllAction = m_menu->addAction(trayIcon("actions/media-playback-stop-symbolic.svg"), tr("Stop All"), this, &SystemTrayIcon::stopAllRequested);
    m_menu->addSeparator();
    m_menu->addAction(trayIcon("actions/preferences-system-symbolic.svg"), tr("Settings…"),     this, &SystemTrayIcon::settingsRequested);
    m_menu->addAction(trayIcon("actions/help-about-symbolic.svg"),        tr("About Stellar"), this, &SystemTrayIcon::aboutRequested);
    m_menu->addSeparator();

    m_speedLimiterAction = m_menu->addAction(trayIcon("actions/speed-limiter-symbolic.svg"), tr("Speed Limiter"), this, [this] {
        if (m_speedLimiterOn)
            emit disableSpeedLimiterRequested();
        else
            emit enableSpeedLimiterRequested();
    });
    m_menu->addAction(trayIcon("actions/configure-symbolic.svg"), tr("Speed Limiter Settings…"), this, &SystemTrayIcon::speedLimiterSettingsRequested);
    m_menu->addSeparator();

    m_pauseSessionAction = m_menu->addAction(trayIcon("actions/media-playback-pause-symbolic.svg"), tr("Pause Session"), this, [this] {
        if (m_sessionPaused)
            emit resumeSessionRequested();
        else
            emit pauseSessionRequested();
    });
    m_menu->addAction(trayIcon("actions/application-exit-symbolic.svg"), tr("Exit Stellar"), this, &SystemTrayIcon::quitRequested);

    m_tray->setContextMenu(m_menu);
#endif

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

void SystemTrayIcon::setTrayIconStyle(int style) {
    if (m_shuttingDown)
        return;
    m_tray->setIcon(trayIconForStyle(style));
}

void SystemTrayIcon::setShuttingDown() {
    if (m_shuttingDown || !m_tray)
        return;
    m_shuttingDown = true;
    const QIcon current = m_tray->icon();
    QIcon grey;
    // Every size the tray might ask for (16/22/24 at 100-300% scaling), so the
    // shell never falls back to the colour pixmap.
    for (const int size : { 16, 20, 22, 24, 32, 44, 48, 64, 66 }) {
        QImage img = current.pixmap(size, size).toImage()
                         .convertToFormat(QImage::Format_ARGB32);
        if (img.isNull())
            continue;
        for (int y = 0; y < img.height(); ++y) {
            auto *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x) {
                // Luminance keeps the logo's shape and contrast; alpha is kept
                // so the rounded corners stay transparent.
                const int g = qGray(line[x]);
                line[x] = qRgba(g, g, g, qAlpha(line[x]));
            }
        }
        grey.addPixmap(QPixmap::fromImage(img));
    }
    if (!grey.isNull())
        m_tray->setIcon(grey);
}

void SystemTrayIcon::show()  { m_tray->show(); }
void SystemTrayIcon::hide()  { m_tray->hide(); }

void SystemTrayIcon::showDownloadsTray()  { m_downloadsTray->show(); }
void SystemTrayIcon::hideDownloadsTray()  { m_downloadsTray->hide(); }
void SystemTrayIcon::setDownloadsTrayToolTip(const QString &tip) { m_downloadsTray->setToolTip(tip); }

void SystemTrayIcon::setToolTip(const QString &tip) {
    m_tray->setToolTip(tip);
}

void SystemTrayIcon::setSpeedLimiterActive(bool active) {
#if defined(Q_OS_LINUX)
    m_speedLimiterOn = active;
    // The text after the tab lands in QMenu's right-aligned shortcut column,
    // matching the QML tray menu's muted "On".
    if (m_speedLimiterAction)
        m_speedLimiterAction->setText(active ? tr("Speed Limiter") + QLatin1Char('\t') + tr("On")
                                             : tr("Speed Limiter"));
#else
    Q_UNUSED(active)
#endif
}

void SystemTrayIcon::setStopAllEnabled(bool enabled) {
#if defined(Q_OS_LINUX)
    if (m_stopAllAction)
        m_stopAllAction->setEnabled(enabled);
#else
    Q_UNUSED(enabled)
#endif
}

void SystemTrayIcon::setSessionPaused(bool paused) {
#if defined(Q_OS_LINUX)
    m_sessionPaused = paused;
    if (m_pauseSessionAction) {
        m_pauseSessionAction->setText(paused ? tr("Resume Session") : tr("Pause Session"));
        m_pauseSessionAction->setIcon(QIcon(QStringLiteral(":/qt/qml/com/stellar/app/app/qml/icons/actions/")
            + (paused ? QStringLiteral("media-playback-start-symbolic.svg") : QStringLiteral("media-playback-pause-symbolic.svg"))));
    }
#else
    Q_UNUSED(paused)
#endif
}

void SystemTrayIcon::showNotification(const QString &title, const QString &msg) {
    const QString safeTitle = title.trimmed().isEmpty()
        ? tr("Stellar Download Manager")
        : title.trimmed();
    const QString safeMsg = msg.trimmed();

    if (m_tray && m_tray->isVisible()
            && QSystemTrayIcon::supportsMessages()) {
        m_tray->showMessage(safeTitle, safeMsg,
                            QSystemTrayIcon::NoIcon, 4000);
        return;
    }

#if defined(STELLAR_LINUX)
    const QString notifySend = QStandardPaths::findExecutable(QStringLiteral("notify-send"));
    if (!notifySend.isEmpty()) {
        // Strip LD_LIBRARY_PATH so system tools don't load our bundled Qt libs.
        QProcess::startDetached(QStringLiteral("env"), {
            QStringLiteral("-u"), QStringLiteral("LD_LIBRARY_PATH"),
            notifySend,
            QStringLiteral("--app-name=Stellar"),
            safeTitle,
            safeMsg
        });
        return;
    }
    const QString kdialog = QStandardPaths::findExecutable(QStringLiteral("kdialog"));
    if (!kdialog.isEmpty()) {
        QProcess::startDetached(QStringLiteral("env"), {
            QStringLiteral("-u"), QStringLiteral("LD_LIBRARY_PATH"),
            kdialog,
            QStringLiteral("--title"), safeTitle,
            QStringLiteral("--passivepopup"), safeMsg,
            QStringLiteral("4")
        });
        return;
    }
    const QString zenity = QStandardPaths::findExecutable(QStringLiteral("zenity"));
    if (!zenity.isEmpty()) {
        QProcess::startDetached(QStringLiteral("env"), {
            QStringLiteral("-u"), QStringLiteral("LD_LIBRARY_PATH"),
            zenity,
            QStringLiteral("--notification"),
            QStringLiteral("--text=%1").arg(QStringLiteral("%1\n%2").arg(safeTitle, safeMsg))
        });
    }
#else
    Q_UNUSED(safeTitle);
    Q_UNUSED(safeMsg);
#endif
}
