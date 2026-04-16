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

#include "FileDragDropHelper.h"
#include <QMimeData>
#include <QDrag>
#include <QUrl>
#include <QGuiApplication>
#include <QWindow>
#include <QDebug>
#include <QPixmap>
#include <QFile>

FileDragDropHelper::FileDragDropHelper(QObject *parent)
    : QObject(parent) {
}

void FileDragDropHelper::startDrag(const QString &filePath) {
    qDebug() << "FileDragDropHelper::startDrag called with path:" << filePath;

    // Verify file exists
    QFile file(filePath);
    if (!file.exists()) {
        qDebug() << "ERROR: File does not exist:" << filePath;
        return;
    }

    qDebug() << "File exists, proceeding with drag";

    // Create mime data with file URL in text/uri-list format
    // This is the standard format that Windows Explorer and other file managers recognize
    QMimeData *mimeData = new QMimeData();

    // Convert file path to URL format (file:///C:/path/to/file)
    // Important: Windows Explorer expects this specific format
    QUrl fileUrl = QUrl::fromLocalFile(filePath);
    qDebug() << "File URL:" << fileUrl.toString();

    QList<QUrl> urls;
    urls.append(fileUrl);

    // Set both text/uri-list and text/plain for maximum compatibility
    // text/uri-list is the standard for file drag-drop operations
    mimeData->setUrls(urls);

    // QDrag requires a QWindow* parent on Linux/Wayland so the compositor can
    // associate the drag session with the source surface. A bare QObject parent
    // causes the Wayland drag-and-drop handshake to fail (drop is rejected).
    // focusWindow() gives us the real window handle; fall back to this object
    // (works on X11/Windows) only when no window is focused.
    QObject *dragParent = QGuiApplication::focusWindow()
                          ? static_cast<QObject *>(QGuiApplication::focusWindow())
                          : this;
    QDrag *drag = new QDrag(dragParent);
    drag->setMimeData(mimeData);

    // Set drag visual (optional - shows the file icon while dragging)
    QPixmap pixmap(32, 32);
    pixmap.fill(Qt::transparent);
    drag->setPixmap(pixmap);

    // Only offer CopyAction — the file stays in the download folder.
    // Offering MoveAction lets file managers silently delete the source.
    qDebug() << "Starting drag operation...";
    Qt::DropAction dropAction = drag->exec(Qt::CopyAction);

    const bool success = (dropAction == Qt::CopyAction);
    qDebug() << (success ? "File drag-drop completed: Copy action" : "File drag-drop cancelled or rejected");
    emit dragCompleted(success);
}
