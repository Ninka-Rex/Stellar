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

#include "TorrentFileModel.h"

#include <functional>
#include <QSet>
#include <QStringList>

TorrentFileModel::TorrentFileModel(QObject *parent)
    : QAbstractListModel(parent) {
    m_root = new Node;
    m_root->isFolder = true;
    m_root->expanded = true;
}

int TorrentFileModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_visibleRows.size();
}

QVariant TorrentFileModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visibleRows.size())
        return {};
    return dataForNode(m_visibleRows.at(index.row()), role);
}

QHash<int, QByteArray> TorrentFileModel::roleNames() const {
    return {
        { NameRole, "name" },
        { PathRole, "path" },
        { SizeRole, "size" },
        { ProgressRole, "progress" },
        { WantedRole, "wanted" },
        { FolderRole, "isFolder" },
        { DepthRole, "depth" },
        { ExpandedRole, "expanded" },
        { FileIndexRole, "fileIndex" }
    };
}

void TorrentFileModel::setEntries(const QVector<Entry> &entries) {
    // Preserve which folders the user has collapsed so a live update doesn't
    // re-expand them or snap the scroll position.
    QSet<QString> collapsedPaths;
    saveCollapsedPaths(m_root, collapsedPaths);

    m_fileEntries = entries;
    clearTree();

    for (const Entry &entry : entries) {
        QString normalizedPath = entry.path;
        normalizedPath.replace(QLatin1Char('\\'), QLatin1Char('/'));
        const QStringList parts = normalizedPath.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        Node *parent = m_root;
        QString currentPath;

        for (int i = 0; i < parts.size(); ++i) {
            const QString &part = parts.at(i);
            if (!currentPath.isEmpty())
                currentPath += QLatin1Char('/');
            currentPath += part;

            Node *child = nullptr;
            for (Node *candidate : parent->children) {
                if (candidate->name == part) {
                    child = candidate;
                    break;
                }
            }

            const bool isLeaf = (i == parts.size() - 1);
            if (!child) {
                child = new Node;
                child->name = part;
                child->path = currentPath;
                child->isFolder = !isLeaf;
                // Restore collapsed state — new folders default to expanded unless
                // the user had explicitly collapsed this path before the update.
                child->expanded = !collapsedPaths.contains(currentPath);
                child->parent = parent;
                child->depth = parent == m_root ? 0 : parent->depth + 1;
                parent->children.push_back(child);
            }

            if (isLeaf) {
                child->size = entry.size;
                child->downloaded = entry.downloaded;
                child->wanted = entry.wanted;
                child->fileIndex = entry.fileIndex;
                child->isFolder = false;
            }

            parent = child;
        }
    }

    recalculateFolderState(m_root);
    rebuildVisibleRows();
}

void TorrentFileModel::updateProgress(const QVector<qint64> &downloadedBytes) {
    if (m_fileEntries.isEmpty())
        return;

    const int limit = qMin(m_fileEntries.size(), downloadedBytes.size());
    for (int i = 0; i < limit; ++i)
        m_fileEntries[i].downloaded = downloadedBytes[i];

    std::function<void(Node *)> updateNode = [&](Node *node) {
        if (!node)
            return;
        if (!node->isFolder && node->fileIndex >= 0 && node->fileIndex < downloadedBytes.size())
            node->downloaded = downloadedBytes[node->fileIndex];
        for (Node *child : node->children)
            updateNode(child);
        if (node->isFolder) {
            node->size = 0;
            node->downloaded = 0;
            for (Node *child : node->children) {
                node->size += child->size;
                node->downloaded += child->downloaded;
            }
        }
    };
    updateNode(m_root);

    if (!m_visibleRows.isEmpty())
        emit dataChanged(index(0), index(m_visibleRows.size() - 1), { ProgressRole, SizeRole });
}

bool TorrentFileModel::setWanted(int row, bool wanted) {
    if (row < 0 || row >= m_visibleRows.size())
        return false;

    Node *node = m_visibleRows.at(row);
    applyWantedRecursive(node, wanted);
    recalculateFolderState(m_root);
    // Wanted state doesn't change which rows are visible — emit dataChanged
    // only, so the ListView scroll position is preserved.
    if (!m_visibleRows.isEmpty())
        emit dataChanged(index(0), index(m_visibleRows.size() - 1), { WantedRole, ProgressRole, SizeRole });
    return true;
}

bool TorrentFileModel::setWantedByFileIndex(int fileIndex, bool wanted) {
    // Scan visible rows for the leaf node matching this libtorrent file index.
    // Visible-row numbers are unstable across expand/collapse; file indices are not.
    for (int row = 0; row < m_visibleRows.size(); ++row) {
        Node *node = m_visibleRows.at(row);
        if (!node->isFolder && node->fileIndex == fileIndex)
            return setWanted(row, wanted);
    }
    return false;
}

bool TorrentFileModel::setWantedByPath(const QString &path, bool wanted) {
    // findNodeByPath searches the tree (not just visible rows), so it works
    // even if the folder is collapsed and has no corresponding visible row.
    Node *node = findNodeByPath(m_root, path);
    if (!node)
        return false;
    applyWantedRecursive(node, wanted);
    recalculateFolderState(m_root);
    if (!m_visibleRows.isEmpty())
        emit dataChanged(index(0), index(m_visibleRows.size() - 1), { WantedRole, ProgressRole, SizeRole });
    return true;
}

bool TorrentFileModel::toggleExpanded(int row) {
    if (row < 0 || row >= m_visibleRows.size())
        return false;
    Node *node = m_visibleRows.at(row);
    if (!node || !node->isFolder)
        return false;

    // Collect the visible descendants that will appear/disappear so we can
    // emit incremental signals instead of a full reset (which scrolls to top).
    QVector<Node *> affected;
    collectDescendants(node, affected);

    if (node->expanded) {
        // Collapsing: remove all currently-visible descendants (rows row+1 .. row+N)
        const int first = row + 1;
        const int last  = row + affected.size();
        if (last >= first) {
            beginRemoveRows({}, first, last);
            m_visibleRows.remove(first, affected.size());
            endRemoveRows();
        }
        node->expanded = false;
    } else {
        // Expanding: compute what rows would become visible and insert them
        node->expanded = true;
        QVector<Node *> toInsert;
        for (Node *child : node->children)
            collectVisibleRows_into(child, toInsert);
        if (!toInsert.isEmpty()) {
            const int first = row + 1;
            const int last  = row + toInsert.size();
            beginInsertRows({}, first, last);
            for (int i = 0; i < toInsert.size(); ++i)
                m_visibleRows.insert(first + i, toInsert.at(i));
            endInsertRows();
        }
    }

    // Notify the folder row itself so the expand arrow updates
    const QModelIndex folderIdx = index(row, 0);
    emit dataChanged(folderIdx, folderIdx, { ExpandedRole });
    return true;
}

bool TorrentFileModel::isSingleFileTarget() const {
    if (m_fileEntries.size() != 1)
        return false;
    const QString path = m_fileEntries.at(0).path;
    return !path.contains(QLatin1Char('/')) && !path.contains(QLatin1Char('\\'));
}

QVariant TorrentFileModel::dataForNode(const Node *node, int role) const {
    if (!node)
        return {};
    switch (role) {
    case NameRole: return node->name;
    case PathRole: return node->path;
    case SizeRole: return node->size;
    case ProgressRole: return node->size > 0 ? double(node->downloaded) / double(node->size) : 0.0;
    case WantedRole: return node->wanted;
    case FolderRole: return node->isFolder;
    case DepthRole: return node->depth;
    case ExpandedRole: return node->expanded;
    case FileIndexRole: return node->fileIndex;
    default: return {};
    }
}

int TorrentFileModel::fileIndexAt(int row) const {
    if (row < 0 || row >= m_visibleRows.size())
        return -1;
    return m_visibleRows.at(row)->fileIndex;
}

bool TorrentFileModel::renameEntry(int row, const QString &newName) {
    if (row < 0 || row >= m_visibleRows.size())
        return false;
    Node *node = m_visibleRows.at(row);
    if (!node || node->isFolder || node->fileIndex < 0)
        return false;
    const QString trimmed = newName.trimmed();
    if (trimmed.isEmpty() || trimmed == node->name)
        return false;

    // Update the node name
    node->name = trimmed;

    // Rebuild the path: keep everything up to the last '/' and append the new name
    const int sep = node->path.lastIndexOf(QLatin1Char('/'));
    if (sep >= 0)
        node->path = node->path.left(sep + 1) + trimmed;
    else
        node->path = trimmed;

    // Keep m_fileEntries in sync so fileEntries() callers see the new name
    if (node->fileIndex < m_fileEntries.size()) {
        m_fileEntries[node->fileIndex].name = trimmed;
        m_fileEntries[node->fileIndex].path = node->path;
    }

    const QModelIndex idx = index(row, 0);
    emit dataChanged(idx, idx, { NameRole, PathRole });
    return true;
}

bool TorrentFileModel::renamePath(const QString &currentPath, const QString &newName) {
    const QString trimmedPath = currentPath.trimmed();
    const QString trimmedName = newName.trimmed();
    if (trimmedPath.isEmpty() || trimmedName.isEmpty())
        return false;

    Node *node = findNodeByPath(m_root, trimmedPath);
    if (!node || node == m_root || trimmedName == node->name)
        return false;

    node->name = trimmedName;
    updatePathsRecursive(node);

    int firstRow = -1;
    int lastRow = -1;
    auto isDescendantOf = [](const Node *candidate, const Node *ancestor) {
        for (auto *cursor = candidate; cursor; cursor = cursor->parent) {
            if (cursor == ancestor)
                return true;
        }
        return false;
    };

    for (int row = 0; row < m_visibleRows.size(); ++row) {
        if (!isDescendantOf(m_visibleRows.at(row), node))
            continue;
        if (firstRow < 0)
            firstRow = row;
        lastRow = row;
    }

    if (firstRow >= 0) {
        emit dataChanged(index(firstRow), index(lastRow), { NameRole, PathRole });
    }
    return true;
}

void TorrentFileModel::clearTree() {
    if (!m_root)
        return;
    for (Node *child : m_root->children)
        deleteNode(child);
    m_root->children.clear();
}

void TorrentFileModel::rebuildVisibleRows() {
    beginResetModel();
    m_visibleRows.clear();
    if (m_root) {
        for (Node *child : m_root->children)
            collectVisibleRows(child);
    }
    endResetModel();
}

void TorrentFileModel::collectVisibleRows(Node *node) {
    if (!node)
        return;
    m_visibleRows.push_back(node);
    if (!node->isFolder || !node->expanded)
        return;
    for (Node *child : node->children)
        collectVisibleRows(child);
}

// Collects nodes that would become visible when expanding — into an external
// vector rather than m_visibleRows, used by the incremental toggleExpanded path.
void TorrentFileModel::collectVisibleRows_into(Node *node, QVector<Node *> &out) {
    if (!node)
        return;
    out.push_back(node);
    if (!node->isFolder || !node->expanded)
        return;
    for (Node *child : node->children)
        collectVisibleRows_into(child, out);
}

// Collects all currently-visible descendants of node (not including node itself).
void TorrentFileModel::collectDescendants(Node *node, QVector<Node *> &out) const {
    if (!node || !node->isFolder || !node->expanded)
        return;
    for (Node *child : node->children) {
        out.push_back(child);
        collectDescendants(child, out);
    }
}

// Walks the tree and records the path of every collapsed folder into out.
void TorrentFileModel::saveCollapsedPaths(Node *node, QSet<QString> &out) const {
    if (!node)
        return;
    for (Node *child : node->children) {
        if (child->isFolder) {
            if (!child->expanded)
                out.insert(child->path);
            saveCollapsedPaths(child, out);
        }
    }
}

void TorrentFileModel::applyWantedRecursive(Node *node, bool wanted) {
    if (!node)
        return;
    node->wanted = wanted;
    if (!node->isFolder && node->fileIndex >= 0 && node->fileIndex < m_fileEntries.size())
        m_fileEntries[node->fileIndex].wanted = wanted;
    for (Node *child : node->children)
        applyWantedRecursive(child, wanted);
}

void TorrentFileModel::recalculateFolderState(Node *node) {
    if (!node)
        return;
    if (!node->isFolder)
        return;

    node->size = 0;
    node->downloaded = 0;
    bool anyWanted = false;
    for (Node *child : node->children) {
        recalculateFolderState(child);
        node->size += child->size;
        node->downloaded += child->downloaded;
        anyWanted = anyWanted || child->wanted;
    }
    if (node != m_root)
        node->wanted = anyWanted;
}

TorrentFileModel::Node *TorrentFileModel::findNodeByPath(Node *node, const QString &path) const {
    if (!node)
        return nullptr;
    if (node != m_root && node->path == path)
        return node;
    for (Node *child : node->children) {
        if (Node *match = findNodeByPath(child, path))
            return match;
    }
    return nullptr;
}

void TorrentFileModel::updatePathsRecursive(Node *node) {
    if (!node)
        return;

    if (node != m_root) {
        if (node->parent == m_root || !node->parent)
            node->path = node->name;
        else
            node->path = node->parent->path + QLatin1Char('/') + node->name;
    }

    if (!node->isFolder && node->fileIndex >= 0 && node->fileIndex < m_fileEntries.size()) {
        m_fileEntries[node->fileIndex].name = node->name;
        m_fileEntries[node->fileIndex].path = node->path;
    }

    for (Node *child : node->children)
        updatePathsRecursive(child);
}

void TorrentFileModel::deleteNode(Node *node) {
    if (!node)
        return;
    for (Node *child : node->children)
        deleteNode(child);
    delete node;
}
