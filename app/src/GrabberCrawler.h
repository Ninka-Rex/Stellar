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
#include <QQueue>
#include <QSet>
#include <QUrl>
#include <QVariantMap>
#include <QPointer>

class QNetworkAccessManager;

class GrabberCrawler : public QObject {
    Q_OBJECT

public:
    explicit GrabberCrawler(QNetworkAccessManager *nam, QObject *parent = nullptr);

    bool isRunning() const { return m_running; }

public slots:
    void start(const QVariantMap &project);
    void cancel();

signals:
    void progressChanged(const QString &statusText);
    void resultFound(const QVariantMap &result);
    void resultMetadataUpdated(const QString &url, qint64 sizeBytes);
    void finished(const QVariantList &results);
    void failed(const QString &message);

private:
    struct PageTask {
        QUrl url;
        int depth{0};
        QString sourcePage;
    };

    struct CrawlResult {
        QString url;
        QString filename;
        QString sourcePage;
        qint64 sizeBytes{-1};
    };

    QNetworkAccessManager *m_nam{nullptr};
    bool m_running{false};
    QVariantMap m_project;
    QQueue<PageTask> m_pendingPages;
    QSet<QString> m_seenPages;
    QSet<QString> m_seenResultKeys;
    QList<CrawlResult> m_results;
    int m_generation{0};
    int m_activeReplies{0};
    int m_activeMetadataReplies{0};
    int m_pagesFetched{0};
    int m_maxConcurrent{4};
    bool m_collectingMetadata{false};
    QUrl m_startUrl;
    QString m_rootDomain;
    QString m_startPathPrefix;
    QQueue<int> m_pendingMetadataRows;

    void pumpQueue();
    void pumpMetadataQueue();
    void finishIfDone();
    void fetchPage(const PageTask &task);
    void probeResultMetadata(int row);
    void processPage(const PageTask &task, const QByteArray &html, const QList<QUrl> &links);
    void maybeQueuePage(const QUrl &url, int depth, const QString &sourcePage);
    void maybeAddFileResult(const QUrl &url, const QString &sourcePage);
    QList<QUrl> extractLinks(const QUrl &baseUrl, const QByteArray &html) const;
    QString normalizeUrl(const QUrl &url) const;
    QString basicAuthHeader() const;
    QString filenameForUrl(const QUrl &url) const;
    QString wildcardToRegex(const QString &pattern) const;
    bool matchesAnyPattern(const QString &text, const QStringList &patterns) const;
    bool shouldExploreUrl(const QUrl &url, int depth) const;
    bool isSameSite(const QUrl &url) const;
    bool isWithinMainDomain(const QUrl &url) const;
    bool isLikelyHtmlPage(const QUrl &url) const;
    bool passesFileFilters(const QUrl &url, const QString &filename) const;
    bool passesSizeFilters(qint64 sizeBytes) const;
};
