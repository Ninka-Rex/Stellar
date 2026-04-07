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
#include <QAbstractTableModel>
#include <QList>
#include "DownloadItem.h"

class DownloadTableModel : public QAbstractTableModel {
    Q_OBJECT
public:
    enum Column {
        ColFilename = 0,
        ColSize,
        ColProgress,
        ColSpeed,
        ColStatus,
        ColTimeLeft,
        ColCount
    };
    Q_ENUM(Column)

    enum Role {
        ProgressRole = Qt::UserRole + 1,
        ItemRole
    };

    explicit DownloadTableModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    int columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void addItem(DownloadItem *item);
    void removeItem(const QString &id);
    DownloadItem *itemAt(int row) const;
    DownloadItem *itemById(const QString &id) const;
    DownloadItem *itemByUrl(const QUrl &url) const;

    Q_INVOKABLE void setFilterCategory(const QString &filter);
    Q_INVOKABLE void sortBy(const QString &column, bool ascending);
    QList<DownloadItem *> allItems() const { return m_items; }

private slots:
    void onItemChanged();
    void rebuildVisible();

private:
    bool matchesFilter(DownloadItem *item) const;

    QList<DownloadItem *> m_items;
    QList<DownloadItem *> m_visible;
    QString               m_filterCategory{QStringLiteral("all")};
    static QString formatSize(qint64 bytes);
    static QString formatSpeed(qint64 bps);
};
