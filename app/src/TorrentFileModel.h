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

#include <QAbstractListModel>
#include <QSet>
#include <QVector>

class TorrentFileModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        SizeRole,
        ProgressRole,
        WantedRole,
        FolderRole,
        DepthRole,
        ExpandedRole,
        FileIndexRole
    };

    struct Entry {
        QString name;
        QString path;
        qint64 size{0};
        qint64 downloaded{0};
        bool wanted{true};
        int fileIndex{-1};
    };

    explicit TorrentFileModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setEntries(const QVector<Entry> &entries);
    void updateProgress(const QVector<qint64> &downloadedBytes);
    Q_INVOKABLE bool setWanted(int row, bool wanted);
    // Stable alternatives that look up by libtorrent file index (leaves) or
    // relative path (folders) so callers don't need a valid visible-row number.
    bool setWantedByFileIndex(int fileIndex, bool wanted);
    bool setWantedByPath(const QString &path, bool wanted);
    Q_INVOKABLE bool toggleExpanded(int row);
    Q_INVOKABLE bool isSingleFileTarget() const;
    Q_INVOKABLE void setLiveUpdatesEnabled(bool enabled) { m_liveUpdatesEnabled = enabled; }
    Q_INVOKABLE bool liveUpdatesEnabled() const { return m_liveUpdatesEnabled; }
    // Returns the libtorrent file index for the given visible row (-1 for folders).
    Q_INVOKABLE int fileIndexAt(int row) const;
    // Optimistically rename the entry at row to newName in the model (call
    // App.renameTorrentFile to also apply the change in libtorrent).
    Q_INVOKABLE bool renameEntry(int row, const QString &newName);
    Q_INVOKABLE bool renamePath(const QString &currentPath, const QString &newName);
    QVector<Entry> fileEntries() const { return m_fileEntries; }
    int fileCount() const { return m_fileEntries.size(); }

private:
    struct Node {
        QString name;
        QString path;
        qint64 size{0};
        qint64 downloaded{0};
        bool wanted{true};
        bool isFolder{false};
        bool expanded{true};
        int depth{0};
        int fileIndex{-1};
        Node *parent{nullptr};
        QVector<Node *> children;
    };

    QVariant dataForNode(const Node *node, int role) const;
    void clearTree();
    void rebuildVisibleRows();
    void collectVisibleRows(Node *node);
    void collectVisibleRows_into(Node *node, QVector<Node *> &out);
    void collectDescendants(Node *node, QVector<Node *> &out) const;
    void saveCollapsedPaths(Node *node, QSet<QString> &out) const;
    void applyWantedRecursive(Node *node, bool wanted);
    void recalculateFolderState(Node *node);
    Node *findNodeByPath(Node *node, const QString &path) const;
    void updatePathsRecursive(Node *node);
    void deleteNode(Node *node);

    Node *m_root{nullptr};
    QVector<Node *> m_visibleRows;
    QVector<Entry> m_fileEntries;
    bool m_liveUpdatesEnabled{true};
};
