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

#include "RssManager.h"

#include "StellarPaths.h"

#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QXmlStreamReader>
#include <algorithm>
#include <utility>

namespace {
QString stableGuid(const QString &guid, const QString &link, const QString &title)
{
    const QString seed = !guid.trimmed().isEmpty() ? guid.trimmed()
                       : !link.trimmed().isEmpty() ? link.trimmed()
                       : title.trimmed();
    return QString::fromLatin1(QCryptographicHash::hash(seed.toUtf8(), QCryptographicHash::Sha1).toHex());
}

QJsonObject articleToJson(const RssManager::StoredArticle &article)
{
    return {
        { QStringLiteral("guid"), article.guid },
        { QStringLiteral("title"), article.title },
        { QStringLiteral("link"), article.link },
        { QStringLiteral("downloadUrl"), article.downloadUrl },
        { QStringLiteral("summary"), article.summary },
        { QStringLiteral("descriptionHtml"), article.descriptionHtml },
        { QStringLiteral("imageUrl"), article.imageUrl },
        { QStringLiteral("published"), article.published.toString(Qt::ISODate) },
        { QStringLiteral("unread"), article.unread },
        { QStringLiteral("isTorrent"), article.isTorrent }
    };
}

RssManager::StoredArticle articleFromJson(const QJsonObject &obj)
{
    RssManager::StoredArticle article;
    article.guid = obj.value(QStringLiteral("guid")).toString();
    article.title = obj.value(QStringLiteral("title")).toString();
    article.link = obj.value(QStringLiteral("link")).toString();
    article.downloadUrl = obj.value(QStringLiteral("downloadUrl")).toString();
    article.summary = obj.value(QStringLiteral("summary")).toString();
    article.descriptionHtml = obj.value(QStringLiteral("descriptionHtml")).toString();
    article.imageUrl = obj.value(QStringLiteral("imageUrl")).toString();
    article.published = QDateTime::fromString(obj.value(QStringLiteral("published")).toString(), Qt::ISODate);
    article.unread = obj.value(QStringLiteral("unread")).toBool(true);
    article.isTorrent = obj.value(QStringLiteral("isTorrent")).toBool(false);
    return article;
}

}

RssManager::RssManager(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent),
      m_nam(nam),
      m_feedModel(new RssFeedModel(this)),
      m_articleModel(new RssArticleModel(this))
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(150);
    connect(&m_saveTimer, &QTimer::timeout, this, &RssManager::save);
    load();
    rebuildModels();
}

void RssManager::setCurrentFeedId(const QString &feedId)
{
    const QString normalized = feedId.trimmed();
    if (m_currentFeedId == normalized)
        return;
    m_currentFeedId = normalized;
    emit currentFeedIdChanged();
    rebuildModels();
}

bool RssManager::addSubscription(const QString &url)
{
    const QString normalized = QUrl::fromUserInput(url.trimmed()).toString();
    if (normalized.isEmpty()) {
        setStatusText(QStringLiteral("Enter a valid RSS or Atom feed URL."));
        return false;
    }
    for (const FeedState &feed : std::as_const(m_feeds)) {
        if (feed.url.compare(normalized, Qt::CaseInsensitive) == 0) {
            setCurrentFeedId(feed.id);
            setStatusText(QStringLiteral("That feed is already subscribed."));
            refreshFeed(feed.id);
            return false;
        }
    }

    FeedState feed;
    feed.id = QString::fromLatin1(QCryptographicHash::hash(normalized.toUtf8(), QCryptographicHash::Sha1).toHex());
    feed.url = normalized;
    feed.title = normalized;
    m_feeds.prepend(feed);
    setCurrentFeedId(feed.id);
    rebuildModels();
    m_saveTimer.start();
    setStatusText(QStringLiteral("Subscription added. Refreshing feed..."));
    refreshFeed(feed.id);
    return true;
}

void RssManager::removeSubscription(const QString &feedId)
{
    const int index = feedIndex(feedId);
    if (index < 0)
        return;
    m_feeds.removeAt(index);
    if (m_currentFeedId == feedId) {
        m_currentFeedId = m_feeds.isEmpty() ? QString() : m_feeds.first().id;
        emit currentFeedIdChanged();
    }
    rebuildModels();
    m_saveTimer.start();
    setStatusText(QStringLiteral("Subscription removed."));
}

bool RssManager::moveSubscription(int from, int to)
{
    if (from < 0 || from >= m_feeds.size() || to < 0 || to >= m_feeds.size() || from == to)
        return false;
    m_feeds.move(from, to);
    rebuildModels();
    m_saveTimer.start();
    return true;
}

bool RssManager::updateSubscription(const QString &feedId, const QString &url, const QString &customTitle)
{
    const int index = feedIndex(feedId);
    if (index < 0)
        return false;

    const QString normalizedUrl = QUrl::fromUserInput(url.trimmed()).toString();
    if (normalizedUrl.isEmpty()) {
        setStatusText(QStringLiteral("Enter a valid RSS or Atom feed URL."));
        return false;
    }

    for (int i = 0; i < m_feeds.size(); ++i) {
        if (i == index)
            continue;
        if (m_feeds.at(i).url.compare(normalizedUrl, Qt::CaseInsensitive) == 0) {
            setStatusText(QStringLiteral("Another subscription already uses that URL."));
            return false;
        }
    }

    FeedState &feed = m_feeds[index];
    const bool urlChanged = feed.url.compare(normalizedUrl, Qt::CaseInsensitive) != 0;
    feed.url = normalizedUrl;
    feed.customTitle = customTitle.trimmed();
    if (urlChanged) {
        feed.etag.clear();
        feed.lastModified.clear();
        feed.errorText.clear();
    }
    rebuildModels();
    m_saveTimer.start();
    setStatusText(QStringLiteral("Subscription updated."));
    if (urlChanged)
        refreshFeed(feed.id);
    return true;
}

void RssManager::refreshAll()
{
    if (m_feeds.isEmpty()) {
        setStatusText(QStringLiteral("Add a feed to get started."));
        return;
    }
    for (int i = 0; i < m_feeds.size(); ++i)
        startFetch(i);
}

void RssManager::refreshFeed(const QString &feedId)
{
    const int index = feedIndex(feedId);
    if (index < 0)
        return;
    startFetch(index);
}

void RssManager::markArticleRead(int row, bool read)
{
    const QVariantMap articleMap = articleData(row);
    const QString feedId = articleMap.value(QStringLiteral("feedId")).toString();
    const QString guid = articleMap.value(QStringLiteral("guid")).toString();
    markArticleReadByGuid(feedId, guid, read);
}

void RssManager::markArticleReadByGuid(const QString &feedId, const QString &guid, bool read)
{
    const int index = feedIndex(feedId);
    if (index < 0)
        return;
    for (StoredArticle &article : m_feeds[index].articles) {
        if (article.guid == guid) {
            article.unread = !read;
            rebuildModels();
            m_saveTimer.start();
            return;
        }
    }
}

void RssManager::markAllRead(const QString &feedId)
{
    bool changed = false;
    for (FeedState &feed : m_feeds) {
        if (!feedId.isEmpty() && feed.id != feedId)
            continue;
        for (StoredArticle &article : feed.articles) {
            if (article.unread) {
                article.unread = false;
                changed = true;
            }
        }
    }
    if (!changed)
        return;
    rebuildModels();
    m_saveTimer.start();
    setStatusText(feedId.isEmpty()
                      ? QStringLiteral("All feed items marked as read.")
                      : QStringLiteral("Feed items marked as read."));
}

QVariantMap RssManager::articleData(int row) const
{
    return m_articleModel->articleData(row);
}

QString RssManager::openArticleLink(int row) const
{
    const QVariantMap data = articleData(row);
    return data.value(QStringLiteral("link")).toString();
}

QString RssManager::downloadUrlForRow(int row) const
{
    const QVariantMap data = articleData(row);
    const QString downloadUrl = data.value(QStringLiteral("downloadUrl")).toString();
    if (!downloadUrl.isEmpty())
        return downloadUrl;
    return data.value(QStringLiteral("link")).toString();
}

void RssManager::load()
{
    QFile file(StellarPaths::rssFeedsFile());
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;
    const QJsonArray array = doc.array();
    m_feeds.clear();
    for (const QJsonValue &value : array) {
        const QJsonObject obj = value.toObject();
        FeedState feed;
        feed.id = obj.value(QStringLiteral("id")).toString();
        feed.url = obj.value(QStringLiteral("url")).toString();
        feed.title = obj.value(QStringLiteral("title")).toString(feed.url);
        feed.customTitle = obj.value(QStringLiteral("customTitle")).toString();
        feed.siteUrl = obj.value(QStringLiteral("siteUrl")).toString();
        feed.description = obj.value(QStringLiteral("description")).toString();
        feed.errorText = obj.value(QStringLiteral("errorText")).toString();
        feed.etag = obj.value(QStringLiteral("etag")).toString();
        feed.lastModified = obj.value(QStringLiteral("lastModified")).toString();
        feed.lastUpdated = QDateTime::fromString(obj.value(QStringLiteral("lastUpdated")).toString(), Qt::ISODate);
        const QJsonArray articleArray = obj.value(QStringLiteral("articles")).toArray();
        for (const QJsonValue &articleValue : articleArray)
            feed.articles.append(articleFromJson(articleValue.toObject()));
        if (!feed.id.isEmpty() && !feed.url.isEmpty())
            m_feeds.append(feed);
    }
    if (!m_feeds.isEmpty())
        m_currentFeedId = m_feeds.first().id;
}

void RssManager::save() const
{
    QJsonArray array;
    for (const FeedState &feed : m_feeds) {
        QJsonArray articles;
        for (const StoredArticle &article : feed.articles)
            articles.append(articleToJson(article));
        array.append(QJsonObject{
            { QStringLiteral("id"), feed.id },
            { QStringLiteral("url"), feed.url },
            { QStringLiteral("title"), feed.title },
            { QStringLiteral("customTitle"), feed.customTitle },
            { QStringLiteral("siteUrl"), feed.siteUrl },
            { QStringLiteral("description"), feed.description },
            { QStringLiteral("errorText"), feed.errorText },
            { QStringLiteral("etag"), feed.etag },
            { QStringLiteral("lastModified"), feed.lastModified },
            { QStringLiteral("lastUpdated"), feed.lastUpdated.toString(Qt::ISODate) },
            { QStringLiteral("articles"), articles }
        });
    }

    QSaveFile file(StellarPaths::rssFeedsFile());
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    file.commit();
}

void RssManager::rebuildModels()
{
    QVector<RssFeedModel::Feed> feeds;
    feeds.reserve(m_feeds.size());
    QVector<RssArticleModel::Article> articles;

    for (const FeedState &feed : m_feeds) {
        int unread = 0;
        for (const StoredArticle &article : feed.articles) {
            if (article.unread)
                ++unread;
            if (m_currentFeedId.isEmpty() || m_currentFeedId == feed.id) {
                articles.append(RssArticleModel::Article{
                    feed.id,
                    feed.customTitle.isEmpty() ? feed.title : feed.customTitle,
                    article.guid,
                    article.title,
                    article.link,
                    article.downloadUrl,
                    article.summary,
                    article.descriptionHtml,
                    article.imageUrl,
                    article.published,
                    article.unread,
                    article.isTorrent
                });
            }
        }
        feeds.append(RssFeedModel::Feed{
            feed.id,
            feed.url,
            feed.customTitle.isEmpty() ? feed.title : feed.customTitle,
            feed.customTitle,
            feed.siteUrl,
            feed.description,
            feed.errorText,
            feed.lastUpdated,
            unread,
            static_cast<int>(feed.articles.size()),
            feed.updating
        });
    }

    std::stable_sort(articles.begin(), articles.end(), [](const auto &lhs, const auto &rhs) {
        if (lhs.published.isValid() && rhs.published.isValid())
            return lhs.published > rhs.published;
        if (lhs.published.isValid() != rhs.published.isValid())
            return lhs.published.isValid();
        return lhs.title.toLower() < rhs.title.toLower();
    });

    m_feedModel->setFeeds(feeds);
    m_articleModel->setArticles(articles);
    emit articleModelChanged();
}

void RssManager::setStatusText(const QString &text)
{
    if (m_statusText == text)
        return;
    m_statusText = text;
    emit statusTextChanged();
}

void RssManager::setRefreshInProgress(bool active)
{
    if (m_refreshInProgress == active)
        return;
    m_refreshInProgress = active;
    emit refreshInProgressChanged();
}

void RssManager::setFeedUpdating(const QString &feedId, bool updating)
{
    const int index = feedIndex(feedId);
    if (index < 0 || m_feeds[index].updating == updating)
        return;
    m_feeds[index].updating = updating;
    // Only update the single changed field — a full rebuildModels() here would fire
    // beginResetModel/endResetModel on every fetch start/finish, which caused the
    // "first <= rowCount(parent)" assert in Qt's delegate model under concurrent refreshes.
    m_feedModel->setFeedUpdating(feedId, updating);
}

int RssManager::feedIndex(const QString &feedId) const
{
    for (int i = 0; i < m_feeds.size(); ++i) {
        if (m_feeds.at(i).id == feedId)
            return i;
    }
    return -1;
}

void RssManager::startFetch(int index)
{
    if (index < 0 || index >= m_feeds.size() || !m_nam)
        return;
    FeedState &feed = m_feeds[index];
    if (feed.updating)
        return;

    QNetworkRequest request(QUrl(feed.url));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader("Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8");
    if (!feed.etag.isEmpty())
        request.setRawHeader("If-None-Match", feed.etag.toUtf8());
    if (!feed.lastModified.isEmpty())
        request.setRawHeader("If-Modified-Since", feed.lastModified.toUtf8());

    QNetworkReply *reply = m_nam->get(request);
    m_replyToFeed.insert(reply, feed.id);
    setFeedUpdating(feed.id, true);
    setRefreshInProgress(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, feedId = feed.id]() {
        handleReplyFinished(feedId, reply);
    });
}

void RssManager::handleReplyFinished(const QString &feedId, QNetworkReply *reply)
{
    const int index = feedIndex(feedId);
    m_replyToFeed.remove(reply);

    if (index < 0) {
        reply->deleteLater();
        setRefreshInProgress(!m_replyToFeed.isEmpty());
        return;
    }

    FeedState &feed = m_feeds[index];
    feed.updating = false;

    if (reply->error() == QNetworkReply::NoError || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 304) {
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 304) {
            feed.errorText.clear();
            feed.lastUpdated = QDateTime::currentDateTimeUtc();
            setStatusText(QStringLiteral("Feed is already up to date."));
        } else {
            QString errorText;
            const ParsedFeed parsed = parseFeedXml(reply->readAll(), reply->url(), &errorText);
            if (!errorText.isEmpty()) {
                feed.errorText = errorText;
                setStatusText(errorText);
            } else {
                const QHash<QString, bool> unreadByGuid = [articles = feed.articles]() {
                    QHash<QString, bool> map;
                    for (const StoredArticle &article : articles)
                        map.insert(article.guid, article.unread);
                    return map;
                }();

                feed.title = parsed.title.isEmpty() ? feed.url : parsed.title;
                feed.siteUrl = parsed.siteUrl;
                feed.description = parsed.description;
                feed.errorText.clear();
                feed.lastUpdated = QDateTime::currentDateTimeUtc();
                feed.etag = QString::fromUtf8(reply->rawHeader("ETag"));
                feed.lastModified = QString::fromUtf8(reply->rawHeader("Last-Modified"));
                feed.articles.clear();
                for (StoredArticle article : parsed.articles) {
                    if (unreadByGuid.contains(article.guid))
                        article.unread = unreadByGuid.value(article.guid);
                    feed.articles.append(article);
                }
                setStatusText(QStringLiteral("Updated \"%1\".").arg(feed.title));
            }
        }
    } else {
        feed.errorText = reply->errorString();
        setStatusText(QStringLiteral("RSS refresh failed: %1").arg(feed.errorText));
    }

    rebuildModels();
    m_saveTimer.start();
    setRefreshInProgress(!m_replyToFeed.isEmpty());
    reply->deleteLater();
}

RssManager::ParsedFeed RssManager::parseFeedXml(const QByteArray &xmlBytes, const QUrl &sourceUrl, QString *errorText) const
{
    ParsedFeed parsed;
    QXmlStreamReader xml(xmlBytes);
    bool sawRoot = false;

    auto resolveUrl = [&sourceUrl](const QString &value) {
        return sourceUrl.resolved(QUrl(value.trimmed())).toString();
    };
    auto elementIs = [&xml](QStringView localName, QStringView qualifiedName = {}) {
        return xml.name() == localName
            || (!qualifiedName.isEmpty() && xml.qualifiedName() == qualifiedName);
    };

    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement())
            continue;

        if (!sawRoot) {
            sawRoot = true;
            if (elementIs(u"rss") || elementIs(u"RDF", u"rdf:RDF")) {
                continue;
            }
            if (elementIs(u"feed")) {
                while (!(xml.isEndElement() && elementIs(u"feed")) && !xml.atEnd()) {
                    xml.readNext();
                    if (!xml.isStartElement())
                        continue;
                    const QString name = xml.name().toString();
                    if (name == QStringLiteral("title")) {
                        parsed.title = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                    } else if (name == QStringLiteral("subtitle")) {
                        parsed.description = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                    } else if (name == QStringLiteral("link")) {
                        const QString rel = xml.attributes().value(QStringLiteral("rel")).toString();
                        const QString href = xml.attributes().value(QStringLiteral("href")).toString();
                        if ((rel.isEmpty() || rel == QStringLiteral("alternate")) && parsed.siteUrl.isEmpty())
                            parsed.siteUrl = resolveUrl(href);
                        if (!xml.isEndElement())
                            xml.skipCurrentElement();
                    } else if (name == QStringLiteral("entry")) {
                        StoredArticle article;
                        QString enclosureUrl;
                        QString enclosureMimeType;
                        while (!(xml.isEndElement() && xml.name() == QStringLiteral("entry")) && !xml.atEnd()) {
                            xml.readNext();
                            if (!xml.isStartElement())
                                continue;
                            const QString childName = xml.name().toString();
                            if (childName == QStringLiteral("id")) {
                                article.guid = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                            } else if (childName == QStringLiteral("title")) {
                                article.title = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                            } else if (childName == QStringLiteral("summary") || childName == QStringLiteral("content")) {
                                const QString html = xml.readElementText(QXmlStreamReader::IncludeChildElements);
                                if (article.descriptionHtml.isEmpty())
                                    article.descriptionHtml = html.trimmed();
                                if (article.summary.isEmpty())
                                    article.summary = simplifyText(html);
                                if (article.imageUrl.isEmpty())
                                    article.imageUrl = extractImageUrl(html, sourceUrl);
                            } else if (childName == QStringLiteral("updated") || childName == QStringLiteral("published")) {
                                if (!article.published.isValid())
                                    article.published = parseDateTime(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                                else
                                    xml.skipCurrentElement();
                            } else if (childName == QStringLiteral("link")) {
                                const QString rel = xml.attributes().value(QStringLiteral("rel")).toString();
                                const QString href = resolveUrl(xml.attributes().value(QStringLiteral("href")).toString());
                                if (rel == QStringLiteral("enclosure")) {
                                    enclosureUrl = href;
                                    enclosureMimeType = xml.attributes().value(QStringLiteral("type")).toString();
                                } else if (rel.isEmpty() || rel == QStringLiteral("alternate")) {
                                    article.link = href;
                                }
                                if (!xml.isEndElement())
                                    xml.skipCurrentElement();
                            } else {
                                xml.skipCurrentElement();
                            }
                        }
                        article.guid = stableGuid(article.guid, article.link, article.title);
                        article.downloadUrl = pickDownloadUrl(article.link, enclosureUrl, enclosureMimeType, &article.isTorrent);
                        if (!article.title.isEmpty())
                            parsed.articles.append(article);
                    } else {
                        xml.skipCurrentElement();
                    }
                }
                break;
            }
        }

        if (xml.name() == QStringLiteral("channel")) {
                while (!(xml.isEndElement() && elementIs(u"channel")) && !xml.atEnd()) {
                xml.readNext();
                if (!xml.isStartElement())
                    continue;
                const QString name = xml.name().toString();
                if (name == QStringLiteral("title")) {
                    parsed.title = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                } else if (name == QStringLiteral("description")) {
                    parsed.description = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                } else if (name == QStringLiteral("link")) {
                    parsed.siteUrl = resolveUrl(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                } else if (name == QStringLiteral("item")) {
                    StoredArticle article;
                    QString enclosureUrl;
                    QString enclosureMimeType;
                    while (!(xml.isEndElement() && elementIs(u"item")) && !xml.atEnd()) {
                        xml.readNext();
                        if (!xml.isStartElement())
                            continue;
                        const QString childName = xml.name().toString();
                        if (childName == QStringLiteral("title")) {
                            article.title = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                        } else if (childName == QStringLiteral("link")) {
                            article.link = resolveUrl(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                        } else if (childName == QStringLiteral("guid")) {
                            article.guid = simplifyText(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                        } else if (childName == QStringLiteral("description")
                                   || xml.qualifiedName() == QStringLiteral("content:encoded")
                                   || childName == QStringLiteral("encoded")) {
                            const QString html = xml.readElementText(QXmlStreamReader::IncludeChildElements);
                            if (article.descriptionHtml.isEmpty())
                                article.descriptionHtml = html.trimmed();
                            if (article.summary.isEmpty())
                                article.summary = simplifyText(html);
                            if (article.imageUrl.isEmpty())
                                article.imageUrl = extractImageUrl(html, sourceUrl);
                        } else if (childName == QStringLiteral("pubDate")
                                   || xml.qualifiedName() == QStringLiteral("dc:date")
                                   || childName == QStringLiteral("date")) {
                            article.published = parseDateTime(xml.readElementText(QXmlStreamReader::IncludeChildElements));
                        } else if (childName == QStringLiteral("enclosure")) {
                            enclosureUrl = resolveUrl(xml.attributes().value(QStringLiteral("url")).toString());
                            enclosureMimeType = xml.attributes().value(QStringLiteral("type")).toString();
                            if (!xml.isEndElement())
                                xml.skipCurrentElement();
                        } else {
                            xml.skipCurrentElement();
                        }
                    }
                    article.guid = stableGuid(article.guid, article.link, article.title);
                    article.downloadUrl = pickDownloadUrl(article.link, enclosureUrl, enclosureMimeType, &article.isTorrent);
                    if (!article.title.isEmpty())
                        parsed.articles.append(article);
                } else {
                    xml.skipCurrentElement();
                }
            }
            break;
        }
    }

    if (xml.hasError() && errorText)
        *errorText = QStringLiteral("The feed could not be parsed.");
    else if (parsed.articles.isEmpty() && parsed.title.isEmpty() && errorText)
        *errorText = QStringLiteral("This URL did not return a valid RSS or Atom feed.");

    return parsed;
}

bool RssManager::looksLikeTorrentUrl(const QString &value)
{
    const QString trimmed = value.trimmed().toLower();
    if (trimmed.startsWith(QStringLiteral("magnet:?"))
            || trimmed.endsWith(QStringLiteral(".torrent"))
            || trimmed.contains(QStringLiteral("xt=urn:btih:")))
        return true;
    // Common torrent-site download path patterns that don't carry a .torrent extension
    // (e.g. https://yts.bz/torrent/download/<hash>)
    const QUrl url(trimmed);
    const QString path = url.path().toLower();
    if (path.contains(QStringLiteral("/torrent/download/"))
            || path.contains(QStringLiteral("/torrents/download/"))
            || path.contains(QStringLiteral("/download/torrent/")))
        return true;
    return false;
}

bool RssManager::looksLikeTorrentMimeType(const QString &mimeType)
{
    const QString lower = mimeType.trimmed().toLower();
    return lower == QStringLiteral("application/x-bittorrent")
        || lower == QStringLiteral("application/x-torrent");
}

QString RssManager::pickDownloadUrl(const QString &link, const QString &enclosureUrl, const QString &enclosureMimeType, bool *isTorrent)
{
    const QString preferred = !enclosureUrl.trimmed().isEmpty() ? enclosureUrl.trimmed() : link.trimmed();
    const bool torrent = looksLikeTorrentMimeType(enclosureMimeType)
                      || looksLikeTorrentUrl(enclosureUrl)
                      || looksLikeTorrentUrl(link);
    if (isTorrent)
        *isTorrent = torrent;
    if (torrent)
        return preferred;
    return enclosureUrl.trimmed();
}

QString RssManager::simplifyText(const QString &value)
{
    QString text = value;
    text.replace(QRegularExpression(QStringLiteral("<[^>]+>")), QStringLiteral(" "));
    text.replace(QStringLiteral("&nbsp;"), QStringLiteral(" "));
    text.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    return text.trimmed();
}

QString RssManager::extractImageUrl(const QString &html, const QUrl &sourceUrl)
{
    static const QRegularExpression imageRegex(
        QStringLiteral(R"(<img\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"][^>]*>)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = imageRegex.match(html);
    if (!match.hasMatch())
        return {};
    return sourceUrl.resolved(QUrl(match.captured(1).trimmed())).toString();
}

QDateTime RssManager::parseDateTime(const QString &value)
{
    const QString trimmed = value.trimmed();
    if (trimmed.isEmpty())
        return {};
    QDateTime dt = QDateTime::fromString(trimmed, Qt::RFC2822Date);
    if (!dt.isValid())
        dt = QDateTime::fromString(trimmed, Qt::ISODate);
    if (!dt.isValid())
        dt = QDateTime::fromString(trimmed, Qt::ISODateWithMs);
    return dt;
}
