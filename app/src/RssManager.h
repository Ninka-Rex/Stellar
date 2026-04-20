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
#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QVector>

#include "RssArticleModel.h"
#include "RssFeedModel.h"

class QNetworkAccessManager;
class QNetworkReply;

class RssManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(RssFeedModel *feedModel READ feedModel CONSTANT)
    Q_PROPERTY(RssArticleModel *articleModel READ articleModel NOTIFY articleModelChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(bool refreshInProgress READ refreshInProgress NOTIFY refreshInProgressChanged)
    Q_PROPERTY(QString currentFeedId READ currentFeedId WRITE setCurrentFeedId NOTIFY currentFeedIdChanged)
    Q_PROPERTY(bool hasFeeds READ hasFeeds NOTIFY articleModelChanged)
    Q_PROPERTY(int feedCount READ feedCount NOTIFY articleModelChanged)
    Q_PROPERTY(int articleCount READ articleCount NOTIFY articleModelChanged)

public:
    struct StoredArticle {
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

    struct FeedState {
        QString id;
        QString url;
        QString title;
        QString customTitle;
        QString siteUrl;
        QString description;
        QString errorText;
        QString etag;
        QString lastModified;
        QDateTime lastUpdated;
        QVector<StoredArticle> articles;
        bool updating{false};
    };

    explicit RssManager(QNetworkAccessManager *nam, QObject *parent = nullptr);

    RssFeedModel *feedModel() const { return m_feedModel; }
    RssArticleModel *articleModel() const { return m_articleModel; }
    QString statusText() const { return m_statusText; }
    bool refreshInProgress() const { return m_refreshInProgress; }
    QString currentFeedId() const { return m_currentFeedId; }
    bool hasFeeds() const { return !m_feeds.isEmpty(); }
    int feedCount() const { return m_feeds.size(); }
    int articleCount() const { return m_articleModel ? m_articleModel->rowCount() : 0; }
    void setCurrentFeedId(const QString &feedId);

    Q_INVOKABLE bool addSubscription(const QString &url);
    Q_INVOKABLE void removeSubscription(const QString &feedId);
    Q_INVOKABLE bool moveSubscription(int from, int to);
    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void refreshFeed(const QString &feedId);
    Q_INVOKABLE bool updateSubscription(const QString &feedId, const QString &url, const QString &customTitle);
    Q_INVOKABLE void markArticleRead(int row, bool read);
    Q_INVOKABLE void markArticleReadByGuid(const QString &feedId, const QString &guid, bool read);
    Q_INVOKABLE void markAllRead(const QString &feedId = {});
    Q_INVOKABLE QVariantMap articleData(int row) const;
    Q_INVOKABLE QString openArticleLink(int row) const;
    Q_INVOKABLE QString downloadUrlForRow(int row) const;
signals:
    void articleModelChanged();
    void statusTextChanged();
    void refreshInProgressChanged();
    void currentFeedIdChanged();
    // Emitted for each article that matches an auto-download rule.
    // savePath/category/queueId may be empty (caller uses defaults).
    void downloadTriggered(const QString &url, const QString &savePath,
                           const QString &category, const QString &queueId,
                           bool isTorrent);

private:
    struct ParsedFeed {
        QString title;
        QString siteUrl;
        QString description;
        QVector<StoredArticle> articles;
    };

    void load();
    void save() const;
    void rebuildModels();
    void setStatusText(const QString &text);
    void setRefreshInProgress(bool active);
    void setFeedUpdating(const QString &feedId, bool updating);
    int feedIndex(const QString &feedId) const;
    void startFetch(int index);
    void handleReplyFinished(const QString &feedId, QNetworkReply *reply);
    void applyAutoDownloadRules(const QString &feedId, const QVector<StoredArticle> &newArticles);
    static bool ruleMatchesArticle(const QJsonObject &rule, const QString &title);
    ParsedFeed parseFeedXml(const QByteArray &xml, const QUrl &sourceUrl, QString *errorText) const;
    static bool looksLikeTorrentUrl(const QString &value);
    static bool looksLikeTorrentMimeType(const QString &mimeType);
    static QString pickDownloadUrl(const QString &link, const QString &enclosureUrl, const QString &enclosureMimeType, bool *isTorrent);
    static QString simplifyText(const QString &value);
    static QString extractImageUrl(const QString &html, const QUrl &sourceUrl);
    static QDateTime parseDateTime(const QString &value);

    QNetworkAccessManager *m_nam{nullptr};
    RssFeedModel *m_feedModel{nullptr};
    RssArticleModel *m_articleModel{nullptr};
    QVector<FeedState> m_feeds;
    QHash<QNetworkReply *, QString> m_replyToFeed;
    QSet<QString> m_autoDownloadedGuids; // GUIDs already triggered, persisted in save file
    QString m_statusText;
    QString m_currentFeedId;
    bool m_refreshInProgress{false};
    QTimer m_saveTimer;
};
