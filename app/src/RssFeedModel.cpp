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

#include "RssFeedModel.h"

#include <QLocale>

RssFeedModel::RssFeedModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RssFeedModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_feeds.size();
}

QVariant RssFeedModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_feeds.size())
        return {};
    const Feed &feed = m_feeds.at(index.row());
    switch (role) {
    case IdRole: return feed.id;
    case TitleRole: return feed.title;
    case UrlRole: return feed.url;
    case SiteUrlRole: return feed.siteUrl;
    case DescriptionRole: return feed.description;
    case ErrorTextRole: return feed.errorText;
    case LastUpdatedRole: return feed.lastUpdated;
    case LastUpdatedDisplayRole: return formatDateTime(feed.lastUpdated);
    case UnreadCountRole: return feed.unreadCount;
    case TotalCountRole: return feed.totalCount;
    case UpdatingRole: return feed.updating;
    case Qt::DisplayRole: return feed.title;
    default: return {};
    }
}

QHash<int, QByteArray> RssFeedModel::roleNames() const
{
    return {
        { IdRole, "feedId" },
        { TitleRole, "title" },
        { UrlRole, "url" },
        { SiteUrlRole, "siteUrl" },
        { DescriptionRole, "description" },
        { ErrorTextRole, "errorText" },
        { LastUpdatedRole, "lastUpdated" },
        { LastUpdatedDisplayRole, "lastUpdatedDisplay" },
        { UnreadCountRole, "unreadCount" },
        { TotalCountRole, "totalCount" },
        { UpdatingRole, "updating" }
    };
}

void RssFeedModel::setFeeds(const QVector<Feed> &feeds)
{
    beginResetModel();
    m_feeds = feeds;
    endResetModel();
}

void RssFeedModel::updateFeed(const Feed &feed)
{
    const int index = indexOfFeed(feed.id);
    if (index < 0) {
        beginInsertRows(QModelIndex(), m_feeds.size(), m_feeds.size());
        m_feeds.append(feed);
        endInsertRows();
        return;
    }
    m_feeds[index] = feed;
    emit dataChanged(this->index(index), this->index(index));
}

void RssFeedModel::removeFeed(const QString &feedId)
{
    const int index = indexOfFeed(feedId);
    if (index < 0)
        return;
    beginRemoveRows(QModelIndex(), index, index);
    m_feeds.removeAt(index);
    endRemoveRows();
}

QVariantMap RssFeedModel::feedData(int row) const
{
    if (row < 0 || row >= m_feeds.size())
        return {};
    const Feed &feed = m_feeds.at(row);
    return {
        { QStringLiteral("feedId"), feed.id },
        { QStringLiteral("title"), feed.title },
        { QStringLiteral("url"), feed.url },
        { QStringLiteral("customTitle"), feed.customTitle },
        { QStringLiteral("siteUrl"), feed.siteUrl },
        { QStringLiteral("description"), feed.description },
        { QStringLiteral("errorText"), feed.errorText },
        { QStringLiteral("lastUpdated"), feed.lastUpdated },
        { QStringLiteral("lastUpdatedDisplay"), formatDateTime(feed.lastUpdated) },
        { QStringLiteral("unreadCount"), feed.unreadCount },
        { QStringLiteral("totalCount"), feed.totalCount },
        { QStringLiteral("updating"), feed.updating }
    };
}

int RssFeedModel::indexOfFeed(const QString &feedId) const
{
    for (int i = 0; i < m_feeds.size(); ++i) {
        if (m_feeds.at(i).id == feedId)
            return i;
    }
    return -1;
}

QString RssFeedModel::formatDateTime(const QDateTime &dateTime)
{
    if (!dateTime.isValid())
        return QStringLiteral("Never");
    return QLocale().toString(dateTime.toLocalTime(), QLocale::ShortFormat);
}
