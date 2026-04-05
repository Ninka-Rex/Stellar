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
#include <QList>
#include <QString>
#include "DownloadItem.h"

// Persists download history to a JSON file.
// File location: QStandardPaths::AppDataLocation / "downloads.json"
class DownloadDatabase : public QObject {
    Q_OBJECT
public:
    explicit DownloadDatabase(QObject *parent = nullptr);

    bool open();

    QList<DownloadItem *> loadAll();
    void save(DownloadItem *item);
    void remove(const QString &id);
    void flush();   // write in-memory state to disk immediately

private:
    void writeToDisk();
    QString m_filePath;

    // In-memory mirror of every item we're tracking, keyed by id.
    // Kept as QVariantMap so we don't need to find the live DownloadItem
    // just to serialise — the item might already be deleted (cancel path).
    QMap<QString, QVariantMap> m_entries;
};
