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
#include <QByteArray>
#include <QHash>
#include <QString>
#include <QVariantMap>
#include <QVector>

class TorrentSearchResultModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        SizeTextRole,
        SizeBytesRole,
        SeedersRole,
        LeechersRole,
        EngineRole,
        PublishedOnRole,
        MagnetLinkRole,
        DescriptionUrlRole
    };

    struct Entry {
        QString name;
        QString sizeText;
        qint64 sizeBytes{-1};
        int seeders{-1};
        int leechers{-1};
        QString engine;
        QString publishedOn;
        QString pluginFile;
        QString downloadLink;
        QString magnetLink;
        QString descriptionUrl;
    };

    explicit TorrentSearchResultModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setEntries(const QVector<Entry> &entries);
    void clear();
    void appendEntry(const Entry &entry);
    Q_INVOKABLE QVariantMap resultData(int row) const;
    Q_INVOKABLE void sortBy(const QString &key, bool ascending);

private:
    bool entryLessThan(const Entry &a, const Entry &b) const;

    QVector<Entry> m_entries;
    QString m_sortKey;
    bool m_sortAscending{true};
};
