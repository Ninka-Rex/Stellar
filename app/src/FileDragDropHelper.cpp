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
#include <QThread>

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

void FileDragDropHelper::startMove(const QString &filePath) {
    QFile file(filePath);
    if (!file.exists()) {
        emit moveCompleted(false);
        return;
    }

    QMimeData *mimeData = new QMimeData();
    QList<QUrl> urls;
    urls.append(QUrl::fromLocalFile(filePath));
    mimeData->setUrls(urls);

    QObject *dragParent = QGuiApplication::focusWindow()
                          ? static_cast<QObject *>(QGuiApplication::focusWindow())
                          : this;
    QDrag *drag = new QDrag(dragParent);
    drag->setMimeData(mimeData);

    QPixmap pixmap(32, 32);
    pixmap.fill(Qt::transparent);
    drag->setPixmap(pixmap);

    // Offer MoveAction so the receiving file manager actually moves the file.
    // We default to MoveAction; the user can hold Ctrl to fall back to Copy.
    // Offer both Copy and Move; Windows Explorer's drop handler performs its
    // own copy regardless of which action we request, so we can't rely on the
    // returned DropAction to tell us whether the user actually dropped on a
    // valid target. Instead, we check drag->target() — if it's non-null, the
    // drop was accepted by *some* OLE drop target (Explorer, another app)
    // and the file has been copied. We then delete the source to complete
    // the move.
    Qt::DropAction dropAction = drag->exec(Qt::CopyAction | Qt::MoveAction, Qt::MoveAction);
    QObject *dropTarget = drag->target();
    qDebug() << "startMove: action=" << dropAction << " target=" << dropTarget;

    // A drop was "accepted" if Qt reports a non-Ignore action OR drag->target()
    // is non-null (Windows Explorer often returns IgnoreAction even after a
    // successful copy because its OLE drop handler bypasses Qt's mechanism).
    const bool accepted = (dropAction != Qt::IgnoreAction) || (dropTarget != nullptr);

    if (accepted) {
        // The receiver (e.g. Explorer) has already copied the file to its
        // destination. Try to remove the source to complete the move. If the
        // file is briefly locked by the receiver, retry a few times. Whether
        // or not the delete eventually succeeds, signal success so the UI
        // reflects that the user's move gesture was accepted.
        for (int i = 0; i < 5; ++i) {
            if (QFile::remove(filePath)) break;
            QThread::msleep(50);
        }
    }
    emit moveCompleted(accepted);
}
