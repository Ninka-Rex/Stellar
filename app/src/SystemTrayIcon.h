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
#include <QPoint>
#include <QSystemTrayIcon>

// SystemTrayIcon wraps QSystemTrayIcon.
// No QMenu/QAction used — those require QApplication (we use QGuiApplication).
// Context menu is handled via QML popup triggered by contextMenuRequested().
class SystemTrayIcon : public QObject {
    Q_OBJECT
public:
    explicit SystemTrayIcon(QObject *parent = nullptr);

    void setup(const QString &iconPath = {});
    void show();
    void hide();
    void setToolTip(const QString &tip);
    void showNotification(const QString &title, const QString &msg);

    // Downloads tray icon (second icon — "SDM downloads")
    void showDownloadsTray();
    void hideDownloadsTray();
    void setDownloadsTrayToolTip(const QString &tip);

signals:
    void showRequested();
    void addUrlRequested();
    void quitRequested();
    void contextMenuRequested(int x, int y);
    void githubRequested();
    void aboutRequested();
    void speedLimiterRequested();

    void downloadsContextMenuRequested(int x, int y);
    void downloadsShowAllRequested();

private:
    QSystemTrayIcon *m_tray{nullptr};
    QSystemTrayIcon *m_downloadsTray{nullptr};
};
