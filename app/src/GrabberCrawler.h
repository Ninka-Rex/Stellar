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

#include "GrabberResultModel.h"

#include <QHash>
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
    // Emitted once per crawled page with all newly discovered files — avoids
    // per-file signal overhead and keeps the model update cost O(1) per page.
    void resultsFound(const QList<GrabberResult> &results);
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

    // Returned by the off-thread classifyLinks task.  All classification work
    // (HTML parsing, JS scan, regex pattern matching) happens off the UI thread;
    // the main-thread callback only does cheap hash-set dedup and queue ops.
    struct OffThreadResult {
        struct PageCandidate {
            QUrl url;
            int depth{0};
            QString sourcePage;
        };
        struct FileCandidate {
            QString url;           // raw URL string
            QString normalizedUrl; // for hideDuplicates=false keying
            QString filename;
            QString sourcePage;
        };
        QList<PageCandidate> pages;
        QList<FileCandidate> files;
        QString progressText;
    };

    QNetworkAccessManager *m_nam{nullptr};
    bool m_running{false};
    // Cache of hostname → isPrivate results so we do at most one blocking DNS
    // lookup per unique host per crawl run (SSRF mitigation for non-IP URLs).
    mutable QHash<QString, bool> m_resolvedHostCache;
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
    QUrl m_startUrl;
    QString m_rootDomain;
    QString m_startPathPrefix;
    QQueue<int> m_pendingMetadataRows;

    void pumpQueue();
    void pumpMetadataQueue();
    void finishIfDone();
    void fetchPage(const PageTask &task);
    void probeResultMetadata(int row);
    // classifyLinks: runs entirely off the UI thread.  Reads only immutable-during-crawl
    // members (m_project, m_startUrl, m_rootDomain, m_startPathPrefix) so no locking needed.
    OffThreadResult classifyLinks(const QUrl &resolvedUrl, const QByteArray &html, int taskDepth) const;
    // Pattern/depth checks from shouldExploreUrl, without the blocking DNS lookup.
    bool checkUrlDepthAndPatterns(const QUrl &url, int depth) const;
    QList<QUrl> extractLinks(const QUrl &baseUrl, const QByteArray &html) const;
    QString normalizeUrl(const QUrl &url) const;
    QString basicAuthHeader() const;
    QString filenameForUrl(const QUrl &url) const;
    QString wildcardToRegex(const QString &pattern) const;
    bool matchesAnyPattern(const QString &text, const QStringList &patterns) const;
    bool isSameSite(const QUrl &url) const;
    bool isWithinMainDomain(const QUrl &url) const;
    static bool isPrivateOrLoopbackHost(const QString &host);
    bool isLikelyHtmlPage(const QUrl &url) const;
    bool passesFileFilters(const QUrl &url, const QString &filename) const;
    bool passesSizeFilters(qint64 sizeBytes) const;
};
