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

#include "RssArticleModel.h"

#include <QLocale>

RssArticleModel::RssArticleModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int RssArticleModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_articles.size();
}

QVariant RssArticleModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_articles.size())
        return {};
    const Article &article = m_articles.at(index.row());
    switch (role) {
    case FeedIdRole: return article.feedId;
    case FeedTitleRole: return article.feedTitle;
    case GuidRole: return article.guid;
    case TitleRole: return article.title;
    case LinkRole: return article.link;
    case DownloadUrlRole: return article.downloadUrl;
    case SummaryRole: return article.summary;
    case DescriptionHtmlRole: return article.descriptionHtml;
    case ImageUrlRole: return article.imageUrl;
    case PublishedRole: return article.published;
    case PublishedDisplayRole: return formatDateTime(article.published);
    case UnreadRole: return article.unread;
    case IsTorrentRole: return article.isTorrent;
    case Qt::DisplayRole: return article.title;
    default: return {};
    }
}

QHash<int, QByteArray> RssArticleModel::roleNames() const
{
    return {
        { FeedIdRole, "feedId" },
        { FeedTitleRole, "feedTitle" },
        { GuidRole, "guid" },
        { TitleRole, "title" },
        { LinkRole, "link" },
        { DownloadUrlRole, "downloadUrl" },
        { SummaryRole, "summary" },
        { DescriptionHtmlRole, "descriptionHtml" },
        { ImageUrlRole, "imageUrl" },
        { PublishedRole, "published" },
        { PublishedDisplayRole, "publishedDisplay" },
        { UnreadRole, "unread" },
        { IsTorrentRole, "isTorrent" }
    };
}

void RssArticleModel::setArticles(const QVector<Article> &articles)
{
    beginResetModel();
    m_articles = articles;
    endResetModel();
}

void RssArticleModel::clear()
{
    if (m_articles.isEmpty())
        return;
    beginResetModel();
    m_articles.clear();
    endResetModel();
}

QVariantMap RssArticleModel::articleData(int row) const
{
    if (row < 0 || row >= m_articles.size())
        return {};
    const Article &article = m_articles.at(row);
    return {
        { QStringLiteral("feedId"), article.feedId },
        { QStringLiteral("feedTitle"), article.feedTitle },
        { QStringLiteral("guid"), article.guid },
        { QStringLiteral("title"), article.title },
        { QStringLiteral("link"), article.link },
        { QStringLiteral("downloadUrl"), article.downloadUrl },
        { QStringLiteral("summary"), article.summary },
        { QStringLiteral("descriptionHtml"), article.descriptionHtml },
        { QStringLiteral("imageUrl"), article.imageUrl },
        { QStringLiteral("published"), article.published },
        { QStringLiteral("publishedDisplay"), formatDateTime(article.published) },
        { QStringLiteral("unread"), article.unread },
        { QStringLiteral("isTorrent"), article.isTorrent }
    };
}

QString RssArticleModel::formatDateTime(const QDateTime &dateTime)
{
    if (!dateTime.isValid())
        return QStringLiteral("Unknown date");
    return QLocale().toString(dateTime.toLocalTime(), QLocale::ShortFormat);
}
