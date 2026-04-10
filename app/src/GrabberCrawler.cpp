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

#include "GrabberCrawler.h"

#include <QByteArray>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QtConcurrent>

GrabberCrawler::GrabberCrawler(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent), m_nam(nam)
{
}

void GrabberCrawler::start(const QVariantMap &project)
{
    cancel();

    const QString startUrlText = project.value(QStringLiteral("startUrl")).toString().trimmed();
    m_startUrl = QUrl::fromUserInput(startUrlText);
    if (!m_startUrl.isValid() || m_startUrl.isEmpty()) {
        emit failed(QStringLiteral("Please enter a valid start page."));
        return;
    }

    m_project = project;
    m_running = true;
    m_pendingPages.clear();
    m_seenPages.clear();
    m_seenResultKeys.clear();
    m_results.clear();
    m_activeReplies = 0;
    m_activeMetadataReplies = 0;
    m_collectingMetadata = false;
    m_pendingMetadataRows.clear();
    m_pagesFetched = 0;
    m_maxConcurrent = qBound(1, project.value(QStringLiteral("filesToExploreAtOnce"), 4).toInt(), 10);
    m_rootDomain = m_startUrl.host().toLower();

    const QString path = m_startUrl.path();
    const int slash = path.lastIndexOf(QLatin1Char('/'));
    m_startPathPrefix = slash >= 0 ? path.left(slash + 1) : QStringLiteral("/");
    if (m_startPathPrefix.isEmpty())
        m_startPathPrefix = QStringLiteral("/");

    m_pendingPages.enqueue({ m_startUrl, 0, QString() });
    emit progressChanged(QStringLiteral("Exploring %1").arg(m_startUrl.toString()));
    pumpQueue();
}

void GrabberCrawler::cancel()
{
    ++m_generation;  // invalidates all in-flight reply lambdas
    m_running = false;
    m_pendingPages.clear();
    m_pendingMetadataRows.clear();
    m_seenPages.clear();
    m_seenResultKeys.clear();
    m_results.clear();
    m_activeReplies = 0;
    m_activeMetadataReplies = 0;
    m_collectingMetadata = false;
}

void GrabberCrawler::pumpQueue()
{
    // Keep a small fixed amount of parallelism so large crawls stay responsive
    // without flooding a host with dozens of simultaneous page requests.
    while (m_running && m_activeReplies < m_maxConcurrent && !m_pendingPages.isEmpty())
        fetchPage(m_pendingPages.dequeue());
    finishIfDone();
}

void GrabberCrawler::finishIfDone()
{
    if (!m_running)
        return;

    if (m_activeReplies > 0 || !m_pendingPages.isEmpty()) {
        return;
    }

    if (!m_collectingMetadata) {
        m_collectingMetadata = true;
        for (int i = 0; i < m_results.size(); ++i)
            m_pendingMetadataRows.enqueue(i);
        pumpMetadataQueue();
        if (!m_pendingMetadataRows.isEmpty() || m_activeMetadataReplies > 0)
            return;
    }

    if (m_activeMetadataReplies > 0 || !m_pendingMetadataRows.isEmpty())
        return;

    QList<CrawlResult> filteredResults;
    filteredResults.reserve(m_results.size());
    for (const CrawlResult &result : m_results) {
        if (passesSizeFilters(result.sizeBytes))
            filteredResults.append(result);
    }
    m_results = filteredResults;

    QVariantList results;
    results.reserve(m_results.size());
    for (const CrawlResult &result : m_results) {
        results.append(QVariantMap{
            { QStringLiteral("checked"), true },
            { QStringLiteral("url"), result.url },
            { QStringLiteral("filename"), result.filename },
            { QStringLiteral("sourcePage"), result.sourcePage },
            { QStringLiteral("sizeBytes"), result.sizeBytes }
        });
    }

    m_running = false;
    emit progressChanged(QStringLiteral("Found %1 files across %2 pages").arg(m_results.size()).arg(m_pagesFetched));
    emit finished(results);
}

void GrabberCrawler::pumpMetadataQueue()
{
    while (m_running && m_activeMetadataReplies < m_maxConcurrent && !m_pendingMetadataRows.isEmpty())
        probeResultMetadata(m_pendingMetadataRows.dequeue());
}

void GrabberCrawler::fetchPage(const PageTask &task)
{
    const QString normalized = normalizeUrl(task.url);
    if (normalized.isEmpty() || m_seenPages.contains(normalized)) {
        pumpQueue();
        return;
    }

    m_seenPages.insert(normalized);

    QNetworkRequest request(task.url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar Grabber"));

    const QString auth = basicAuthHeader();
    if (!auth.isEmpty())
        request.setRawHeader("Authorization", auth.toUtf8());

    QNetworkReply *reply = m_nam->get(request);
    ++m_activeReplies;
    const int gen = m_generation;

    connect(reply, &QNetworkReply::finished, this, [this, reply, task, gen]() {
        if (gen != m_generation) {
            reply->deleteLater();
            return;
        }
        --m_activeReplies;

        if (!m_running) {
            reply->deleteLater();
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            emit progressChanged(QStringLiteral("Skipped %1").arg(task.url.toString()));
            reply->deleteLater();
            pumpQueue();
            return;
        }

        const QByteArray html = reply->readAll();
        const QUrl resolvedUrl = reply->url();
        reply->deleteLater();

        // Run the expensive HTML parsing off the UI thread.
        // Capture everything by value; the watcher continuation runs back on the
        // main thread so it is safe to call processPage / pumpQueue there.
        const PageTask resolvedTask{ resolvedUrl, task.depth, task.sourcePage };
        auto *watcher = new QFutureWatcher<QList<QUrl>>(this);
        connect(watcher, &QFutureWatcher<QList<QUrl>>::finished, this,
                [this, watcher, resolvedTask, html, gen]() {
            watcher->deleteLater();
            if (gen != m_generation) return;
            if (!m_running) return;
            ++m_pagesFetched;
            processPage(resolvedTask, html, watcher->result());
            pumpQueue();
        });
        // extractLinks is const and only reads html + baseUrl — safe to run in parallel
        watcher->setFuture(QtConcurrent::run(
            [this, resolvedUrl, html]() { return extractLinks(resolvedUrl, html); }
        ));
    });
}

void GrabberCrawler::processPage(const PageTask &task, const QByteArray &html, const QList<QUrl> &links)
{
    emit progressChanged(QStringLiteral("Exploring %1").arg(task.url.toString()));
    for (const QUrl &link : links) {
        if (!link.isValid())
            continue;

        if (isLikelyHtmlPage(link))
            maybeQueuePage(link, task.depth + 1, task.url.toString());
        else
            maybeAddFileResult(link, task.url.toString());
    }

    if (m_project.value(QStringLiteral("processJavaScript")).toBool()) {
        // This is intentionally conservative: we look for explicit URLs inside
        // script text, but we do not execute remote JavaScript during crawling.
        static const QRegularExpression quotedUrlRe(
            QStringLiteral(R"((https?:\/\/[^"'\\\s<>]+))"),
            QRegularExpression::CaseInsensitiveOption);
        const QString text = QString::fromUtf8(html);
        QRegularExpressionMatchIterator it = quotedUrlRe.globalMatch(text);
        while (it.hasNext()) {
            const QString raw = it.next().captured(1);
            const QUrl url = QUrl::fromUserInput(raw);
            if (isLikelyHtmlPage(url))
                maybeQueuePage(url, task.depth + 1, task.url.toString());
            else
                maybeAddFileResult(url, task.url.toString());
        }
    }
}

void GrabberCrawler::maybeQueuePage(const QUrl &url, int depth, const QString &sourcePage)
{
    if (!shouldExploreUrl(url, depth))
        return;
    const QString normalized = normalizeUrl(url);
    if (normalized.isEmpty() || m_seenPages.contains(normalized))
        return;
    m_pendingPages.enqueue({ url, depth, sourcePage });
}

void GrabberCrawler::maybeAddFileResult(const QUrl &url, const QString &sourcePage)
{
    if (!url.isValid())
        return;

    const QString filename = filenameForUrl(url);
    if (!passesFileFilters(url, filename))
        return;

    QString duplicateKey = filename.toLower();
    if (!m_project.value(QStringLiteral("hideDuplicateFiles")).toBool())
        duplicateKey = normalizeUrl(url);

    if (m_seenResultKeys.contains(duplicateKey))
        return;
    m_seenResultKeys.insert(duplicateKey);

    const QString urlText = url.toString();
    m_results.append({ urlText, filename, sourcePage, -1 });
    emit resultFound(QVariantMap{
        { QStringLiteral("checked"), true },
        { QStringLiteral("url"), urlText },
        { QStringLiteral("filename"), filename },
        { QStringLiteral("sourcePage"), sourcePage },
        { QStringLiteral("sizeBytes"), -1 }
    });
    emit progressChanged(QStringLiteral("Found %1 files across %2 pages").arg(m_results.size()).arg(m_pagesFetched));
}

void GrabberCrawler::probeResultMetadata(int row)
{
    if (row < 0 || row >= m_results.size())
        return;

    const QUrl url = QUrl::fromUserInput(m_results.at(row).url);
    if (!url.isValid())
        return;

    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar Grabber"));

    const QString auth = basicAuthHeader();
    if (!auth.isEmpty())
        request.setRawHeader("Authorization", auth.toUtf8());

    QNetworkReply *reply = m_nam->head(request);
    ++m_activeMetadataReplies;
    const int gen = m_generation;
    emit progressChanged(QStringLiteral("Contacting server for file size (%1/%2)")
                         .arg(row + 1).arg(m_results.size()));

    connect(reply, &QNetworkReply::finished, this, [this, reply, row, gen]() {
        if (gen != m_generation) {
            reply->deleteLater();
            return;
        }
        --m_activeMetadataReplies;

        if (m_running && row >= 0 && row < m_results.size() && reply->error() == QNetworkReply::NoError) {
            const qint64 contentLength = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
            if (contentLength > 0) {
                m_results[row].sizeBytes = contentLength;
                emit resultMetadataUpdated(m_results[row].url, contentLength);
            }
        }

        reply->deleteLater();
        if (m_running) {
            pumpMetadataQueue();
            finishIfDone();
        }
    });
}

QList<QUrl> GrabberCrawler::extractLinks(const QUrl &baseUrl, const QByteArray &html) const
{
    QList<QUrl> links;
    const QString text = QString::fromUtf8(html);

    static const QRegularExpression attrRe(
        QStringLiteral(R"((href|src)\s*=\s*["']([^"'#]+)["'])"),
        QRegularExpression::CaseInsensitiveOption);

    QRegularExpressionMatchIterator it = attrRe.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch match = it.next();
        const QString rawLink = match.captured(2).trimmed();
        if (rawLink.isEmpty()
            || rawLink.startsWith(QStringLiteral("javascript:"), Qt::CaseInsensitive)
            || rawLink.startsWith(QStringLiteral("mailto:"), Qt::CaseInsensitive)
            || rawLink.startsWith(QStringLiteral("data:"), Qt::CaseInsensitive)) {
            continue;
        }
        links.append(baseUrl.resolved(QUrl(rawLink)));
    }

    return links;
}

QString GrabberCrawler::normalizeUrl(const QUrl &url) const
{
    if (!url.isValid())
        return {};
    QUrl copy(url);
    copy.setFragment(QString());
    return copy.adjusted(QUrl::NormalizePathSegments).toString(QUrl::FullyEncoded);
}

QString GrabberCrawler::basicAuthHeader() const
{
    const QString username = m_project.value(QStringLiteral("username")).toString();
    const QString password = m_project.value(QStringLiteral("password")).toString();
    if (username.isEmpty() && password.isEmpty())
        return {};
    return QStringLiteral("Basic ") + QString::fromLatin1((username + QStringLiteral(":") + password).toUtf8().toBase64());
}

QString GrabberCrawler::filenameForUrl(const QUrl &url) const
{
    QString filename = QFileInfo(url.path()).fileName();
    if (filename.isEmpty())
        filename = QStringLiteral("index.html");
    return filename;
}

QString GrabberCrawler::wildcardToRegex(const QString &pattern) const
{
    QString regex = QRegularExpression::escape(pattern);
    regex.replace(QStringLiteral("\\*"), QStringLiteral(".*"));
    return QStringLiteral("^") + regex + QStringLiteral("$");
}

bool GrabberCrawler::matchesAnyPattern(const QString &text, const QStringList &patterns) const
{
    for (const QString &pattern : patterns) {
        const QString trimmed = pattern.trimmed();
        if (trimmed.isEmpty())
            continue;
        const QRegularExpression re(wildcardToRegex(trimmed), QRegularExpression::CaseInsensitiveOption);
        if (re.match(text).hasMatch())
            return true;
    }
    return false;
}

bool GrabberCrawler::shouldExploreUrl(const QUrl &url, int depth) const
{
    if (!url.isValid())
        return false;

    const QString scheme = url.scheme().toLower();
    if (scheme != QStringLiteral("http") && scheme != QStringLiteral("https"))
        return false;

    bool sameSite = isSameSite(url);
    if (!sameSite && m_project.value(QStringLiteral("exploreMainDomain")).toBool())
        sameSite = isWithinMainDomain(url);

    int maxDepth = m_project.value(QStringLiteral("exploreOtherLevels"), 0).toInt();
    if (sameSite)
        maxDepth = m_project.value(QStringLiteral("exploreThisLevels"), 0).toInt();
    if (depth > maxDepth)
        return false;

    const QString urlText = normalizeUrl(url);
    const QStringList includePatterns = m_project.value(QStringLiteral("exploreIncludePatterns")).toStringList();
    const QStringList excludePatterns = m_project.value(QStringLiteral("exploreExcludePatterns")).toStringList()
        + m_project.value(QStringLiteral("logoutPatterns")).toStringList();

    if (!includePatterns.isEmpty() && !matchesAnyPattern(urlText, includePatterns))
        return false;
    if (matchesAnyPattern(urlText, excludePatterns))
        return false;

    if (m_project.value(QStringLiteral("dontExploreParentDirectories")).toBool() && sameSite) {
        const QString path = url.path();
        if (!path.startsWith(m_startPathPrefix))
            return false;
    }

    return true;
}

bool GrabberCrawler::isSameSite(const QUrl &url) const
{
    return url.host().compare(m_startUrl.host(), Qt::CaseInsensitive) == 0;
}

bool GrabberCrawler::isWithinMainDomain(const QUrl &url) const
{
    const QString host = url.host().toLower();
    return host == m_rootDomain || host.endsWith(QStringLiteral(".") + m_rootDomain);
}

bool GrabberCrawler::isLikelyHtmlPage(const QUrl &url) const
{
    const QString path = url.path().toLower();
    if (path.endsWith(QLatin1Char('/')) || path.isEmpty())
        return true;

    const QString suffix = QFileInfo(path).suffix().toLower();
    if (suffix.isEmpty())
        return true;

    static const QSet<QString> htmlLike{
        QStringLiteral("html"), QStringLiteral("htm"), QStringLiteral("php"),
        QStringLiteral("asp"), QStringLiteral("aspx"), QStringLiteral("jsp"),
        QStringLiteral("jspx"), QStringLiteral("cfm"), QStringLiteral("cgi"),
        QStringLiteral("shtml"), QStringLiteral("xhtml")
    };
    return htmlLike.contains(suffix);
}

bool GrabberCrawler::passesFileFilters(const QUrl &url, const QString &filename) const
{
    const QString urlText = normalizeUrl(url);
    const QString path = url.path();

    if (m_project.value(QStringLiteral("searchFilesOnThisSiteOnly")).toBool()
        && !isSameSite(url)
        && !(m_project.value(QStringLiteral("exploreMainDomain")).toBool() && isWithinMainDomain(url))) {
        return false;
    }

    const QStringList includePatterns = m_project.value(QStringLiteral("fileIncludePatterns")).toStringList();
    const QStringList excludePatterns = m_project.value(QStringLiteral("fileExcludePatterns")).toStringList();
    const QStringList pathIncludes = m_project.value(QStringLiteral("filePathIncludePatterns")).toStringList();
    const QStringList pathExcludes = m_project.value(QStringLiteral("filePathExcludePatterns")).toStringList();

    if (!includePatterns.isEmpty()
        && !matchesAnyPattern(filename, includePatterns)
        && !matchesAnyPattern(urlText, includePatterns)) {
        return false;
    }

    if (matchesAnyPattern(filename, excludePatterns) || matchesAnyPattern(urlText, excludePatterns))
        return false;
    if (!pathIncludes.isEmpty() && !matchesAnyPattern(path, pathIncludes) && !matchesAnyPattern(urlText, pathIncludes))
        return false;
    if (matchesAnyPattern(path, pathExcludes) || matchesAnyPattern(urlText, pathExcludes))
        return false;

    return true;
}

bool GrabberCrawler::passesSizeFilters(qint64 sizeBytes) const
{
    const qint64 minSize = m_project.value(QStringLiteral("minSizeBytes"), -1).toLongLong();
    const qint64 maxSize = m_project.value(QStringLiteral("maxSizeBytes"), -1).toLongLong();

    if ((minSize > 0 || maxSize > 0) && sizeBytes <= 0)
        return false;
    if (minSize > 0 && sizeBytes < minSize)
        return false;
    if (maxSize > 0 && sizeBytes > maxSize)
        return false;
    return true;
}
