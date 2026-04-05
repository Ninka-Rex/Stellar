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

    // Create drag object with copy action
    // DropAction can be CopyAction or MoveAction depending on what you want
    QDrag *drag = new QDrag(this);
    drag->setMimeData(mimeData);

    // Set drag visual (optional - shows the file icon while dragging)
    QPixmap pixmap(32, 32);
    pixmap.fill(Qt::transparent);
    drag->setPixmap(pixmap);

    // Execute the drag operation
    // This is a blocking call that returns when drop completes
    qDebug() << "Starting drag operation...";
    Qt::DropAction dropAction = drag->exec(Qt::CopyAction | Qt::MoveAction);

    bool success = false;
    if (dropAction == Qt::MoveAction) {
        qDebug() << "File drag-drop completed: Move action";
        success = true;
    } else if (dropAction == Qt::CopyAction) {
        qDebug() << "File drag-drop completed: Copy action";
        success = true;
    } else {
        qDebug() << "File drag-drop was cancelled or rejected";
        success = false;
    }

    emit dragCompleted(success);
}
