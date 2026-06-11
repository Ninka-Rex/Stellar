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
#include <QHostAddress>
#include <QHostInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QtConcurrent>

// Cap the bytes we read from any single crawled page. An HTML page that is
// larger than this is almost certainly not a real navigation page, and a
// hostile host could otherwise stream gigabytes to exhaust memory (DoS). We
// only ever parse the prefix; links beyond the cap are not harvested.
static constexpr qint64 kMaxPageBytes = 16LL * 1024 * 1024; // 16 MiB

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
    m_pendingGuards = 0;
    m_pendingMetadataRows.clear();
    m_pagesFetched = 0;
    m_maxConcurrent = qBound(1, project.value(QStringLiteral("filesToExploreAtOnce"), 4).toInt(), 10);
    m_rootDomain = m_startUrl.host().toLower();

    const QString path = m_startUrl.path();
    const int slash = path.lastIndexOf(QLatin1Char('/'));
    m_startPathPrefix = slash >= 0 ? path.left(slash + 1) : QStringLiteral("/");
    if (m_startPathPrefix.isEmpty())
        m_startPathPrefix = QStringLiteral("/");

    // Precompile every pattern list on the (single-threaded) main thread before
    // any worker starts. classifyLinks() runs on QtConcurrent threads and matches
    // patterns concurrently; a lazy cache mutated from those threads is a data
    // race on QHash (corruption/crash). Populating it fully here makes it
    // immutable for the duration of the crawl, so the worker-thread reads are safe.
    m_patternCache.clear();
    const QStringList patternKeys = {
        QStringLiteral("exploreIncludePatterns"),
        QStringLiteral("exploreExcludePatterns"),
        QStringLiteral("logoutPatterns"),
        QStringLiteral("fileIncludePatterns"),
        QStringLiteral("fileExcludePatterns"),
        QStringLiteral("filePathIncludePatterns"),
        QStringLiteral("filePathExcludePatterns")
    };
    QSet<QString> primed;
    auto prime = [&](const QStringList &patterns) {
        if (patterns.isEmpty())
            return;
        const QString cacheKey = patterns.join(QLatin1Char('\0'));
        if (primed.contains(cacheKey))
            return;
        primed.insert(cacheKey);
        compilePatterns(cacheKey, patterns);
    };
    for (const QString &key : patternKeys)
        prime(project.value(key).toStringList());
    // checkUrlDepthAndPatterns concatenates explore-exclude + logout patterns into
    // a single list, so prime that combined key too.
    prime(project.value(QStringLiteral("exploreExcludePatterns")).toStringList()
          + project.value(QStringLiteral("logoutPatterns")).toStringList());

    // SSRF: the start URL is user-supplied and otherwise unchecked. Gate it
    // through the same host guard as discovered links so a start URL pointing at
    // a private/loopback/metadata address is never fetched.
    emit progressChanged(QStringLiteral("Exploring %1").arg(m_startUrl.toString()));
    const int gen = m_generation;
    const QUrl startUrl = m_startUrl;
    guardHostThen(startUrl.host().toLower(), gen, [this, startUrl]() {
        m_pendingPages.enqueue({ startUrl, 0, QString() });
        pumpQueue();
    }, [this]() {
        m_running = false;
        emit failed(QStringLiteral("Start page resolves to a private or local network address."));
    });
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
    m_pendingGuards = 0;
    m_resolvedHostCache.clear();
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

    // An async host guard may still be resolving and could re-enqueue a page or
    // probe. Don't finish until all are settled.
    if (m_pendingGuards > 0)
        return;

    // Metadata probing runs concurrently with crawling (started in maybeAddFileResult),
    // so by the time the last page finishes there may still be in-flight HEAD replies
    // or queued rows.  Wait for those to drain before emitting finished().
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
    // Metadata HEAD requests run concurrently with page crawling using a fixed
    // budget of 4 slots, independent of the page-fetch concurrency limit.
    // This keeps the metadata queue draining throughout the crawl rather than
    // only starting after all pages are done.
    static constexpr int kMaxMetadataConcurrent = 4;
    while (m_running && m_activeMetadataReplies < kMaxMetadataConcurrent && !m_pendingMetadataRows.isEmpty())
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
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar Grabber"));

    // Only send credentials to the same origin as the crawl start URL to prevent
    // credential leakage when the crawler follows links to third-party hosts.
    const bool sameOrigin = task.url.host().compare(m_startUrl.host(), Qt::CaseInsensitive) == 0
                         && task.url.scheme() == m_startUrl.scheme();
    const QString auth = sameOrigin ? basicAuthHeader() : QString();
    if (!auth.isEmpty()) {
        request.setRawHeader("Authorization", auth.toUtf8());
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::SameOriginRedirectPolicy);
    } else {
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
    }

    QNetworkReply *reply = m_nam->get(request);
    ++m_activeReplies;
    const int gen = m_generation;

    // SSRF: re-check every redirect hop (NoLessSafeRedirectPolicy permits
    // cross-host redirects, which could target a private/loopback address).
    guardRedirects(reply, gen);

    // Memory-DoS guard: abort as soon as the body exceeds the page cap rather
    // than buffering an unbounded response from a hostile host.
    connect(reply, &QNetworkReply::downloadProgress, this,
            [reply](qint64 received, qint64 /*total*/) {
        if (received > kMaxPageBytes)
            reply->abort();
    });

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

        QByteArray html = reply->readAll();
        if (html.size() > kMaxPageBytes)
            html.truncate(static_cast<int>(kMaxPageBytes));
        const QUrl resolvedUrl = reply->url();
        reply->deleteLater();

        // Run ALL expensive classification work off the UI thread:
        // HTML parsing, JS URL extraction, isLikelyHtmlPage, pattern/depth
        // checks, and regex-based file-filter matching.  The watcher callback
        // on the main thread only does cheap hash-set dedup and queue ops.
        const int taskDepth = task.depth;
        auto *watcher = new QFutureWatcher<OffThreadResult>(this);
        connect(watcher, &QFutureWatcher<OffThreadResult>::finished, this,
                [this, watcher, resolvedUrl, gen]() {
            watcher->deleteLater();
            if (gen != m_generation) return;
            if (!m_running) return;
            ++m_pagesFetched;

            const OffThreadResult result = watcher->result();
            emit progressChanged(result.progressText);

            // ── Candidate pages ────────────────────────────────────────────
            // Every candidate is SSRF-gated through guardHostThen: literal IPs
            // resolve synchronously, hostnames via async DNS, and only safe
            // hosts are enqueued. Unsafe hosts are silently dropped.
            for (const OffThreadResult::PageCandidate &cand : result.pages) {
                const QString host = cand.url.host().toLower();
                guardHostThen(host, gen, [this, cand]() {
                    const QString normalized = normalizeUrl(cand.url);
                    if (normalized.isEmpty() || m_seenPages.contains(normalized)) return;
                    m_pendingPages.enqueue({ cand.url, cand.depth, cand.sourcePage });
                    pumpQueue();
                });
            }

            // ── Candidate files ────────────────────────────────────────────
            // Collect all new files for this page into one list, dedup against
            // m_seenResultKeys, then emit a single batch signal.  This avoids
            // per-file signal overhead and reduces model notifications from
            // O(files_per_page) to O(1) per crawled page.
            QList<GrabberResult> newResults;
            for (const OffThreadResult::FileCandidate &cand : result.files) {
                const QString duplicateKey =
                    m_project.value(QStringLiteral("hideDuplicateFiles")).toBool()
                        ? cand.filename.toLower()
                        : cand.normalizedUrl;
                if (m_seenResultKeys.contains(duplicateKey))
                    continue;
                m_seenResultKeys.insert(duplicateKey);

                const int newRow = m_results.size();
                m_results.append({ cand.url, cand.filename, cand.sourcePage, -1 });
                m_pendingMetadataRows.enqueue(newRow);

                GrabberResult gr;
                gr.checked  = true;
                gr.url       = cand.url;
                gr.filename  = cand.filename;
                gr.sourcePage = cand.sourcePage;
                gr.sizeBytes  = -1;
                newResults.append(gr);
            }
            if (!newResults.isEmpty()) {
                emit resultsFound(newResults);
                emit progressChanged(QStringLiteral("Found %1 files across %2 pages")
                                     .arg(m_results.size()).arg(m_pagesFetched));
                pumpMetadataQueue();
            }

            pumpQueue();
        });
        watcher->setFuture(QtConcurrent::run(
            [this, resolvedUrl, html, taskDepth]() -> OffThreadResult {
                return classifyLinks(resolvedUrl, html, taskDepth);
            }
        ));
    });
}

// ── Off-thread classification ─────────────────────────────────────────────────
// Runs inside QtConcurrent::run — must only access immutable-during-crawl members:
// m_project, m_startUrl, m_rootDomain, m_startPathPrefix.
// Mutable state (m_seenPages, m_seenResultKeys, m_resolvedHostCache) is touched
// only in the main-thread watcher callback, never here.
GrabberCrawler::OffThreadResult GrabberCrawler::classifyLinks(
    const QUrl &resolvedUrl,
    const QByteArray &html,
    int taskDepth) const
{
    OffThreadResult out;
    out.progressText = QStringLiteral("Exploring %1").arg(resolvedUrl.toString());
    const QString sourcePage = resolvedUrl.toString();

    // Harvest all raw links from the HTML.
    QList<QUrl> links = extractLinks(resolvedUrl, html);

    // Optionally scan script text for explicit https?:// URLs.
    // This is intentionally conservative: we search for quoted URL literals
    // but do not execute JavaScript.
    if (m_project.value(QStringLiteral("processJavaScript")).toBool()) {
        static const QRegularExpression quotedUrlRe(
            QStringLiteral(R"((https?:\/\/[^"'\\\s<>]+))"),
            QRegularExpression::CaseInsensitiveOption);
        const QString text = QString::fromUtf8(html);
        QRegularExpressionMatchIterator it = quotedUrlRe.globalMatch(text);
        while (it.hasNext()) {
            const QUrl url = QUrl::fromUserInput(it.next().captured(1));
            if (url.isValid())
                links.append(url);
        }
    }

    for (const QUrl &link : links) {
        if (!link.isValid())
            continue;

        if (isLikelyHtmlPage(link)) {
            // checkUrlDepthAndPatterns does all shouldExploreUrl checks except
            // DNS — the DNS cache lookup happens on the main thread (fast hash
            // lookup) and async resolution is scheduled there too.
            if (checkUrlDepthAndPatterns(link, taskDepth + 1))
                out.pages.append({ link, taskDepth + 1, sourcePage });
        } else {
            const QString filename = filenameForUrl(link);
            if (filename.isEmpty())
                continue;
            if (!passesFileFilters(link, filename))
                continue;
            out.files.append({ link.toString(), normalizeUrl(link), filename, sourcePage });
        }
    }

    return out;
}

// Pattern/depth subset of the old shouldExploreUrl — no DNS, safe to call off-thread.
bool GrabberCrawler::checkUrlDepthAndPatterns(const QUrl &url, int depth) const
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
        if (!url.path().startsWith(m_startPathPrefix))
            return false;
    }

    return true;
}


void GrabberCrawler::probeResultMetadata(int row)
{
    if (row < 0 || row >= m_results.size())
        return;

    const QUrl url = QUrl::fromUserInput(m_results.at(row).url);
    if (!url.isValid())
        return;

    const int gen = m_generation;

    // SSRF: file-result HEAD probes are outbound requests to link targets, so
    // they need the same host gate as page fetches. An unsafe host is dropped;
    // the metadata queue keeps draining via the pump below.
    guardHostThen(url.host().toLower(), gen, [this, url, row, gen]() {
        if (gen != m_generation || !m_running)
            return;

        QNetworkRequest request(url);
        request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Stellar Grabber"));

        const bool sameOrigin = url.host().compare(m_startUrl.host(), Qt::CaseInsensitive) == 0
                             && url.scheme() == m_startUrl.scheme();
        const QString auth = sameOrigin ? basicAuthHeader() : QString();
        if (!auth.isEmpty()) {
            request.setRawHeader("Authorization", auth.toUtf8());
            request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                                 QNetworkRequest::SameOriginRedirectPolicy);
        } else {
            request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                                 QNetworkRequest::NoLessSafeRedirectPolicy);
        }

        QNetworkReply *reply = m_nam->head(request);
        ++m_activeMetadataReplies;
        guardRedirects(reply, gen);
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
    }, [this]() {
        // Host blocked: no reply was created, so drain the next queued row and
        // re-evaluate completion (guardHostThen already released its pending slot).
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

const QList<QRegularExpression> &GrabberCrawler::compilePatterns(const QString &cacheKey,
                                                                 const QStringList &patterns) const
{
    auto it = m_patternCache.find(cacheKey);
    if (it != m_patternCache.end())
        return *it;
    QList<QRegularExpression> compiled;
    compiled.reserve(patterns.size());
    for (const QString &pattern : patterns) {
        const QString trimmed = pattern.trimmed();
        if (trimmed.isEmpty())
            continue;
        compiled.append(QRegularExpression(wildcardToRegex(trimmed),
                                           QRegularExpression::CaseInsensitiveOption));
    }
    return *m_patternCache.insert(cacheKey, std::move(compiled));
}

bool GrabberCrawler::matchesAnyPattern(const QString &text, const QStringList &patterns) const
{
    if (patterns.isEmpty())
        return false;

    // Read-only lookup: the cache is fully populated by compilePatterns() in
    // start() on the main thread before any worker runs, so this runs lock-free
    // on QtConcurrent threads. A pattern list not seen at start() (shouldn't
    // happen) falls back to matching nothing rather than mutating the cache from
    // a worker thread, which would be a data race.
    const QString cacheKey = patterns.join(QLatin1Char('\0'));
    auto it = m_patternCache.constFind(cacheKey);
    if (it == m_patternCache.constEnd())
        return false;

    for (const QRegularExpression &re : *it) {
        if (re.match(text).hasMatch())
            return true;
    }
    return false;
}

void GrabberCrawler::guardHostThen(const QString &host, int gen,
                                   std::function<void()> onSafe,
                                   std::function<void()> onBlocked)
{
    auto blocked = [onBlocked]() { if (onBlocked) onBlocked(); };

    // Cached result — synchronous decision.
    if (m_resolvedHostCache.contains(host)) {
        if (m_resolvedHostCache.value(host)) { blocked(); return; }
        onSafe();
        return;
    }

    // Literal IP — decide synchronously, no DNS.
    QHostAddress literalAddr;
    if (literalAddr.setAddress(host)) {
        const bool isPrivate = isPrivateOrLoopbackHost(host);
        m_resolvedHostCache[host] = isPrivate;
        if (isPrivate) { blocked(); return; }
        onSafe();
        return;
    }

    // Hostname: resolve asynchronously. Mark blocked until DNS confirms safe so
    // concurrent candidates for the same host don't all spawn lookups, and so a
    // never-completing lookup fails closed. The callback fires onSafe/onBlocked.
    m_resolvedHostCache[host] = true;
    ++m_pendingGuards;
    QHostInfo::lookupHost(host, this,
        [this, host, gen, onSafe, blocked](const QHostInfo &info) {
            --m_pendingGuards;
            if (gen != m_generation || !m_running)
                return;
            bool isPrivate = info.addresses().isEmpty(); // no address resolved → fail closed
            for (const QHostAddress &addr : info.addresses()) {
                if (isPrivateOrLoopbackHost(addr.toString())) {
                    isPrivate = true;
                    break;
                }
            }
            m_resolvedHostCache[host] = isPrivate;
            if (isPrivate)
                blocked();
            else
                onSafe();
            // onSafe/onBlocked may have re-enqueued work (or not); either way the
            // pending-guard count just dropped, so re-evaluate completion to avoid
            // a crawl that hangs because the last outstanding item was a guard.
            finishIfDone();
        });
}

void GrabberCrawler::guardRedirects(QNetworkReply *reply, int gen)
{
    // NoLessSafeRedirectPolicy still permits cross-host redirects to private/
    // loopback targets. Re-check each hop's host; abort the reply on an unsafe
    // target. Literal IPs are checked inline; for hostnames we conservatively
    // abort if the host isn't already cached as safe (a DNS round-trip here would
    // race the redirect, so fail closed rather than follow blindly).
    connect(reply, &QNetworkReply::redirected, this,
            [this, reply, gen](const QUrl &target) {
        if (gen != m_generation) {
            reply->abort();
            return;
        }
        const QString host = target.host().toLower();
        QHostAddress literalAddr;
        if (literalAddr.setAddress(host)) {
            if (isPrivateOrLoopbackHost(host))
                reply->abort();
            return;
        }
        // Hostname: only follow if a prior guard already proved this host safe.
        const auto it = m_resolvedHostCache.constFind(host);
        if (it == m_resolvedHostCache.constEnd() || it.value())
            reply->abort();
    });
}

// SECURITY: SSRF protection (CWE-918).
// The crawler accepts a start URL from the user, follows links, and makes
// outbound HTTP requests.  Without this check, a malicious website can
// redirect the crawler to internal network addresses (loopback, RFC-1918,
// link-local) to probe services that are not publicly reachable — including
// the AWS/GCP instance-metadata endpoint at 169.254.169.254 which can yield
// cloud credentials.
//
// We resolve the host string to a QHostAddress (handles both literal IPs and
// hostnames that were already resolved by Qt before we see them here) and
// then check Qt's built-in isLoopback() / isLinkLocal() predicates plus
// manual range checks for the RFC-1918 private ranges that Qt does not expose
// as a single predicate.
bool GrabberCrawler::isPrivateOrLoopbackHost(const QString &host)
{
    QHostAddress addr;
    if (!addr.setAddress(host))
        return false; // hostname, not a literal IP — DNS resolution happens later; can't block here

    if (addr.isLoopback() || addr.isLinkLocal())
        return true;

    // IPv4 private ranges: 10/8, 172.16/12, 192.168/16 (RFC 1918)
    // and CGNAT 100.64/10 (RFC 6598) which is also non-routable.
    if (addr.protocol() == QAbstractSocket::IPv4Protocol) {
        const quint32 ip = addr.toIPv4Address();
        const quint32 a  = (ip >> 24) & 0xFF;
        const quint32 b  = (ip >> 16) & 0xFF;
        if (a == 10)                          return true; // 10.0.0.0/8
        if (a == 172 && b >= 16 && b <= 31)   return true; // 172.16.0.0/12
        if (a == 192 && b == 168)             return true; // 192.168.0.0/16
        if (a == 100 && b >= 64 && b <= 127)  return true; // 100.64.0.0/10 CGNAT
    }

    // IPv6 unique-local fc00::/7
    if (addr.protocol() == QAbstractSocket::IPv6Protocol) {
        const Q_IPV6ADDR v6 = addr.toIPv6Address();
        if ((v6[0] & 0xFE) == 0xFC) return true; // fc00::/7
    }

    return false;
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
