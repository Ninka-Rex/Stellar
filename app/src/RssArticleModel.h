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

class RssArticleModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Role {
        FeedIdRole = Qt::UserRole + 1,
        FeedTitleRole,
        GuidRole,
        TitleRole,
        LinkRole,
        DownloadUrlRole,
        SummaryRole,
        DescriptionHtmlRole,
        ImageUrlRole,
        PublishedRole,
        PublishedDisplayRole,
        UnreadRole,
        IsTorrentRole
    };

    struct Article {
        QString feedId;
        QString feedTitle;
        QString guid;
        QString title;
        QString link;
        QString downloadUrl;
        QString summary;
        QString descriptionHtml;
        QString imageUrl;
        QDateTime published;
        bool unread{true};
        bool isTorrent{false};
    };

    explicit RssArticleModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setArticles(const QVector<Article> &articles);
    void clear();
    Q_INVOKABLE QVariantMap articleData(int row) const;

private:
    static QString formatDateTime(const QDateTime &dateTime);

    QVector<Article> m_articles;
};
