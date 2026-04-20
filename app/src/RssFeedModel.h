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
#include <QDateTime>
#include <QVector>

class RssFeedModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        UrlRole,
        SiteUrlRole,
        DescriptionRole,
        ErrorTextRole,
        LastUpdatedRole,
        LastUpdatedDisplayRole,
        UnreadCountRole,
        TotalCountRole,
        UpdatingRole
    };

    struct Feed {
        QString id;
        QString url;
        QString title;
        QString customTitle;
        QString siteUrl;
        QString description;
        QString errorText;
        QDateTime lastUpdated;
        int unreadCount{0};
        int totalCount{0};
        bool updating{false};
    };

    explicit RssFeedModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setFeeds(const QVector<Feed> &feeds);
    void updateFeed(const Feed &feed);
    void setFeedUpdating(const QString &feedId, bool updating);
    void removeFeed(const QString &feedId);
    Q_INVOKABLE QVariantMap feedData(int row) const;

private:
    int indexOfFeed(const QString &feedId) const;
    static QString formatDateTime(const QDateTime &dateTime);

    QVector<Feed> m_feeds;
};
