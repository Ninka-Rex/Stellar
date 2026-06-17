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

#include "YtdlpTransfer.h"
#include "FileNameUtils.h"
#include <QRegularExpression>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTimer>
#include <cmath>
#include <limits>

namespace {
// yt-dlp progress lines are untrusted; a garbled value+unit can parse to a
// finite-but-absurd bytes/sec that prints "388548235 MB/s" and overflows
// downstream int casts. Reject anything above ~50 GB/s.
qint64 sanitizeSpeed(qint64 bytesPerSec) {
    constexpr qint64 kMaxSaneSpeed = 50LL * 1000 * 1000 * 1000;
    return (bytesPerSec < 0 || bytesPerSec > kMaxSaneSpeed) ? 0 : bytesPerSec;
}
}

// ── Constructor / Destructor ──────────────────────────────────────────────────

YtdlpTransfer::YtdlpTransfer(DownloadItem *item,
                              const QString    &ytdlpPath,
                              const QString    &formatSel,
                              const QString    &containerFormat,
                              const QString    &saveDir,
                              const QString    &ffmpegPath,
                              int               speedLimitKBps,
                              bool              resume,
                              const QString    &outputTemplate,
                              const QString    &proxyUrl,
                              bool              playlistMode,
                              int               maxItems,
                              const YtdlpOptions &options,
                              const QString    &jsRuntimePath,
                              const QString    &jsRuntimeName,
                              bool              forceOverwrites,
                              QObject          *parent)
    : QObject(parent)
    , m_item(item)
    , m_ytdlpPath(ytdlpPath)
    , m_formatSel(formatSel)
    , m_containerFormat(containerFormat.isEmpty() ? QStringLiteral("mp4") : containerFormat)
    , m_saveDir(saveDir)
    , m_ffmpegPath(ffmpegPath)
    , m_speedLimitKBps(speedLimitKBps)
    , m_resume(resume)
    , m_outputTemplate([&outputTemplate]() -> QString {
        const QString tmpl = outputTemplate.trimmed().isEmpty()
            ? QStringLiteral("%(title)s.%(ext)s")
            : outputTemplate.trimmed();
        // Reject templates that contain literal path separators or parent-directory
        // references outside of yt-dlp variable expansions (e.g. %(playlist_index)s).
        // The check strips all %(...)s tokens first so only the literal skeleton
        // of the template is inspected — yt-dlp sanitizes variable values itself.
        static const QRegularExpression kVarToken(QStringLiteral("%\\([^)]*\\)[diouxefgcrsa]?s?"));
        QString skeleton = tmpl;
        skeleton.remove(kVarToken);
        const bool hasSeparator = skeleton.contains(QLatin1Char('/'))
                               || skeleton.contains(QLatin1Char('\\'));
        const bool hasParentRef = skeleton.contains(QStringLiteral(".."));
        if (hasSeparator || hasParentRef) {
            qWarning() << "[YtdlpTransfer] Output template contains path traversal; using default.";
            return QStringLiteral("%(title)s.%(ext)s");
        }
        return tmpl;
    }())
    , m_proxyUrl(proxyUrl)
    , m_playlistMode(playlistMode)
    , m_maxItems(maxItems)
    , m_options(options)
    , m_jsRuntimePath(jsRuntimePath)
    , m_jsRuntimeName(jsRuntimeName)
    , m_forceOverwrites(forceOverwrites)
{
}

YtdlpTransfer::~YtdlpTransfer() {
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->kill();
        m_process->waitForFinished(2000);
    }
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

void YtdlpTransfer::start() {
    if (m_process) return;

    // Determine whether the selected container is audio-only.
    // Audio containers use --extract-audio + --audio-format instead of
    // --merge-output-format so yt-dlp produces a single audio file.
    static const QStringList kAudioContainers = {
        QStringLiteral("mp3"),  QStringLiteral("m4a"), QStringLiteral("aac"),
        QStringLiteral("opus"), QStringLiteral("flac"),QStringLiteral("wav"),
        QStringLiteral("vorbis")
    };
    const bool isAudioOnly = kAudioContainers.contains(m_containerFormat.toLower());

    // Build the yt-dlp command-line arguments:
    //   --no-playlist            ignore playlist containers; download one item
    //   --newline                emit one progress line per update (no CR overwrite)
    //   --no-warnings            keep stdout clean; errors go to stderr (merged)
    //   -f <selector>            format/quality selector
    //   --merge-output-format    produce the chosen video container (e.g. mp4, mkv)
    //   --extract-audio          (audio-only) discard video; re-encode to audio format
    //   --audio-format <fmt>     (audio-only) target audio codec/container
    //   --audio-quality 0        (audio-only) best VBR quality
    //   --paths <dir>            destination directory
    //   -o <template>            filename template using video metadata
    //   --no-part                write directly; no .part temp files left on abort
    //   --ffmpeg-location <path> explicit ffmpeg binary (if bundled/custom)
    //   --windows-filenames      strip illegal Windows path characters (Windows only)
    //   --continue               (optional) resume a partial download
    QStringList args;
    args << QStringLiteral("--ignore-config");
    if (m_playlistMode) {
        args << QStringLiteral("--yes-playlist");
        if (m_options.playlistReverse) {
            // Reverse order via Python slice "::-1"; combine with maxItems limit if set.
            // "::-1" alone downloads all in reverse; "1:N:1" then "::-1" is not composable
            // in a single expression, so when both are set we take the first N then reverse
            // by using negative stop: e.g. maxItems=10 → "::-1" and rely on the user
            // understanding that reverse+limit isn't a single-expression combo yt-dlp
            // supports cleanly. Simplest correct behaviour: reverse full list when
            // maxItems is 0; when maxItems > 0, download last N in forward order (newest
            // last, which with reverse gives newest-first N items: "-N:" slice).
            if (m_maxItems > 0)
                args << QStringLiteral("--playlist-items")
                     << QStringLiteral("-") + QString::number(m_maxItems) + QStringLiteral(":");
            else
                args << QStringLiteral("--playlist-items") << QStringLiteral("::-1");
        } else if (m_maxItems > 0) {
            // playlist-items uses a Python-slice range: "1:N" downloads the first N items
            args << QStringLiteral("--playlist-items")
                 << QStringLiteral("1:") + QString::number(m_maxItems);
        }
    } else {
        args << QStringLiteral("--no-playlist");
    }
    args << QStringLiteral("--newline")
         << QStringLiteral("--no-warnings");
    // Empty format selector means "let yt-dlp decide" — used when probe returned
    // no format info (e.g. channel URLs).  Skip -f entirely so yt-dlp uses its
    // built-in default (bestvideo+bestaudio/best), which is correct for channels.
    if (!m_formatSel.isEmpty())
        args << QStringLiteral("-f") << m_formatSel;

    if (isAudioOnly) {
        // Extract and re-encode to the requested audio format.
        args << QStringLiteral("--extract-audio")
             << QStringLiteral("--audio-format") << m_containerFormat
             << QStringLiteral("--audio-quality") << QStringLiteral("0");
    } else {
        // Merge video + audio streams into the chosen container.
        args << QStringLiteral("--merge-output-format") << m_containerFormat;
    }

    args << QStringLiteral("--paths") << m_saveDir
         << QStringLiteral("-o") << m_outputTemplate;
    // --no-part writes directly to the final file (no .part temp file).
    // Skip when resuming: yt-dlp needs the .part file to know the resume offset.
    if (!m_resume)
        args << QStringLiteral("--no-part");

    // Tell yt-dlp where ffmpeg is if we have a non-default location.
    if (!m_ffmpegPath.isEmpty())
        args << QStringLiteral("--ffmpeg-location") << m_ffmpegPath;

    // ── Rate limit (per-download override takes precedence over global) ────────
    const int effectiveRate = (m_options.rateLimitKBps > 0) ? m_options.rateLimitKBps
                                                             : m_speedLimitKBps;
    if (effectiveRate > 0)
        args << QStringLiteral("--limit-rate") << QString::number(effectiveRate) + QStringLiteral("K");

    if (m_resume)
        args << QStringLiteral("--continue");

    // User chose "Overwrite existing file" in the duplicate dialog: force yt-dlp
    // to overwrite rather than silently skip an existing file. Without this the
    // backend's collision scan would have renamed the output to <name>_2.
    if (m_forceOverwrites)
        args << QStringLiteral("--force-overwrites");

    // yt-dlp does not inherit Qt's application-level proxy — it must be told explicitly.
    // Pass an empty string to "--proxy" to force yt-dlp to use NO proxy (overrides
    // any system proxy that might otherwise be picked up from environment variables).
    if (!m_proxyUrl.isEmpty())
        args << QStringLiteral("--proxy") << m_proxyUrl;
    else
        args << QStringLiteral("--proxy") << QStringLiteral("");  // explicit "no proxy"

    // ── Subtitles ─────────────────────────────────────────────────────────────
    if (m_options.writeSubs || m_options.writeAutoSubs) {
        if (m_options.writeAutoSubs)
            args << QStringLiteral("--write-auto-subs");
        else
            args << QStringLiteral("--write-subs");
        if (!m_options.subLangs.trimmed().isEmpty())
            args << QStringLiteral("--sub-langs") << m_options.subLangs.trimmed();
        if (m_options.embedSubs)
            args << QStringLiteral("--embed-subs");
    }

    // ── Post-processing ───────────────────────────────────────────────────────
    if (m_options.embedThumbnail)
        args << QStringLiteral("--embed-thumbnail");
    if (m_options.embedMetadata)
        args << QStringLiteral("--embed-metadata");
    if (m_options.sponsorBlock)
        // "default" removes: sponsor, selfpromo, interaction, intro, outro (all but filler)
        args << QStringLiteral("--sponsorblock-remove") << QStringLiteral("default");

    // ── Filters / access ─────────────────────────────────────────────────────
    if (!m_options.dateAfter.trimmed().isEmpty())
        args << QStringLiteral("--dateafter") << m_options.dateAfter.trimmed();
    if (!m_options.cookiesFromBrowser.trimmed().isEmpty()) {
        args << QStringLiteral("--cookies-from-browser") << m_options.cookiesFromBrowser.trimmed();
        // Browser cookies can make yt-dlp prefer YouTube's web_creator client
        // for some accounts; without a PO token that can make requested formats
        // vanish. Keep the regular clients for cookie-based retries.
        // Do NOT pass extractor-args when using browser cookies.
        // yt-dlp's with-cookie default (tv_downgraded,web_safari for free accounts)
        // already filters out POT-requiring formats automatically — the
        // formats=missing_pot flag we use in the probe would expose those
        // non-downloadable formats and cause "Requested format is not available".
    }

    // ── Output extras ─────────────────────────────────────────────────────────
    if (m_options.writeDescription)
        args << QStringLiteral("--write-description");
    if (m_options.writeThumbnailFile)
        args << QStringLiteral("--write-thumbnail");
    if (m_options.splitChapters)
        args << QStringLiteral("--split-chapters");
    if (!m_options.downloadSections.trimmed().isEmpty())
        args << QStringLiteral("--download-sections") << m_options.downloadSections.trimmed();

    // ── Playlist extras ───────────────────────────────────────────────────────
    if (m_options.playlistRandom)
        args << QStringLiteral("--playlist-random");
    if (m_options.liveFromStart)
        args << QStringLiteral("--live-from-start");
    if (m_options.useArchive)
        args << QStringLiteral("--download-archive")
             << m_saveDir + QStringLiteral("/yt-dlp-archive.txt");
    if (m_options.ignoreErrors)
        args << QStringLiteral("--ignore-errors");
    if (m_options.waitForVideoSecs > 0)
        args << QStringLiteral("--wait-for-video") << QString::number(m_options.waitForVideoSecs);
    if (m_options.concurrentFragments > 1)
        args << QStringLiteral("--concurrent-fragments") << QString::number(m_options.concurrentFragments);

    // ── JS runtime for EJS YouTube n-challenge solver ─────────────────────────
    // yt-dlp 2026.03.17+ requires an external JS runtime (deno/node/bun/quickjs)
    // to execute EJS scripts that solve YouTube's n-parameter throttling challenge.
    // Without this, YouTube URLs return only storyboard formats (no real video/audio).
    // Format: --js-runtimes <name>:/path/to/binary
    if (!m_jsRuntimePath.isEmpty() && !m_jsRuntimeName.isEmpty()) {
        args << QStringLiteral("--js-runtimes")
             << (m_jsRuntimeName + QLatin1Char(':') + m_jsRuntimePath);
    }

    // ── Exact per-item titles (playlist mode) ─────────────────────────────────
    // We can't use --print here: it forces --quiet in yt-dlp, which suppresses the
    // "[download] Downloading item N of M", "Destination:" and progress lines this
    // class relies on — leaving the channel progress dialog blank with no activity.
    // Instead --progress-template injects the exact (untruncated, UTF-8) title and
    // playlist index INTO the download progress line, without implying --quiet. The
    // U+001F unit separators (never present in titles) frame our fields so the
    // parser can pick them out from yt-dlp's own progress text.
    if (m_playlistMode) {
        args << QStringLiteral("--progress-template")
             << QStringLiteral("download:\x1FSTPROG\x1F%(info.playlist_index)s\x1F%(info.title)s\x1F%(progress._percent)s\x1F%(progress.total_bytes)s\x1F%(progress.total_bytes_estimate)s\x1F%(progress.speed)s\x1F%(progress.eta)s\x1F%(progress.downloaded_bytes)s\x1F%(info.filesize_approx)s\x1F");
    }

    args << m_item->url().toString();

    m_process = new QProcess(this);
    m_process->setProgram(m_ytdlpPath);
    m_process->setArguments(args);
    // Merge stderr into stdout so a single readyRead handler captures everything,
    // including error messages when a download fails.
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    // Force UTF-8 output from Python/yt-dlp so Unicode characters in video titles
    // (curly quotes, em-dashes, CJK, etc.) are decoded correctly on Windows.
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("PYTHONUTF8"),       QStringLiteral("1"));
        env.insert(QStringLiteral("PYTHONIOENCODING"), QStringLiteral("utf-8"));
        m_process->setProcessEnvironment(env);
    }

    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &YtdlpTransfer::onReadyReadStdout);
    connect(m_process,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &YtdlpTransfer::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred,
            this, &YtdlpTransfer::onProcessError);

    // Mark the item as actively downloading and capable of being resumed
    m_item->setLastTryAt(QDateTime::currentDateTime());
    m_item->setStatus(DownloadItem::Status::Downloading);
    m_item->setResumeCapable(true);

    // Snapshot the save directory before launching so the fallback filename
    // reconciliation on completion can restrict its search to files that are
    // genuinely new or grew since this transfer started, rather than any file
    // that happens to be recent in a busy shared folder.
    m_preLaunchSnapshot.clear();
    {
        const QFileInfoList existing = QDir(m_saveDir).entryInfoList(
            QDir::Files | QDir::NoDotAndDotDot);
        m_preLaunchSnapshot.reserve(existing.size());
        for (const QFileInfo &fi : existing)
            m_preLaunchSnapshot.insert(fi.fileName(), fi.size());
    }

    m_process->start();
    emit started();
    qDebug() << "[YtdlpTransfer] started:" << m_ytdlpPath << args;
}

// Tear down the yt-dlp subprocess WITHOUT blocking the GUI thread. The old code
// called waitForFinished(3000), freezing the UI for up to 3 s. Instead we detach
// our slots, kill the process, and let it self-reap: deleteLater fires on the
// process's own finished() signal, or unconditionally as a fallback so a process
// that never reports exit is still freed.
void YtdlpTransfer::killProcessAsync() {
    if (!m_process)
        return;
    QProcess *proc = m_process;
    m_process = nullptr;
    disconnect(proc, nullptr, this, nullptr);
    connect(proc, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            proc, &QObject::deleteLater);
    proc->kill();
    // Fallback: if finished() never arrives (zombie/detached), free after a
    // grace period anyway. Does not block — runs on the event loop.
    QTimer::singleShot(5000, proc, &QObject::deleteLater);
}

void YtdlpTransfer::pause() {
    killProcessAsync();
    m_item->setStatus(DownloadItem::Status::Paused);
    m_item->setSpeed(0);
}

void YtdlpTransfer::abort() {
    m_aborted = true;
    killProcessAsync();
    m_item->setSpeed(0);
}

// ── Stdout reading ────────────────────────────────────────────────────────────

void YtdlpTransfer::onReadyReadStdout() {
    if (!m_process) return;

    // Append new data and dispatch every complete line.
    m_lineBuf += m_process->readAllStandardOutput();

    int nl;
    while ((nl = m_lineBuf.indexOf('\n')) >= 0) {
        const QString line = QString::fromUtf8(m_lineBuf.left(nl)).trimmed();
        m_lineBuf.remove(0, nl + 1);
        if (!line.isEmpty())
            handleLine(line);
    }
}

void YtdlpTransfer::advancePlaylistItem(int newIndex) {
    if (!m_playlistMode || newIndex <= m_playlistStartedIndex)
        return;
    // Any items between the last-started and the new one are now finished. (Items
    // skipped by the download archive jump the index forward; mark them done too.)
    for (int done = m_playlistStartedIndex; done > 0 && done < newIndex; ++done) {
        emit playlistItemProgress(done, 100.0);
        emit playlistItemFinished(done);
    }
    m_playlistStartedIndex = newIndex;
}

void YtdlpTransfer::handleLine(const QString &line) {
    if (m_playlistMode) {
        // ── Custom progress line from --progress-template ──────────────────────
        // Emitted every progress tick as (U+001F = separator, never in titles):
        //   \x1FSTPROG\x1F<index>\x1F<title>\x1F<downloaded>\x1F<total>\x1F
        //     <total_estimate>\x1F<speed>\x1F<eta>\x1F
        // The title here is the raw, untruncated, correctly-encoded value from
        // yt-dlp's info_dict — unlike the console "Downloading item" line which
        // carries no title at all and the legacy "[download] X%" text which is
        // styled/truncated. Missing numeric fields render as "NA".
        // (QString::trimmed() strips the outer separators since 0x1F < 0x20, so we
        // match on the marker token and split on the surviving internal ones.)
        if (line.startsWith(QStringLiteral("STPROG\x1F"))) {
            const QStringList p = line.split(QChar(0x1F));
            // p: ["STPROG", index, title, percent, total, total_est, speed, eta,
            //     downloaded, filesize_approx]
            // Numeric fields are raw yt-dlp values; missing ones render as "NA".
            // total_bytes/estimate/speed can be floats ("1234.0"), so parse as
            // double, not int.
            if (p.size() >= 8) {
                const int idx = p.at(1).toInt();
                if (idx > 0) {
                    advancePlaylistItem(idx);
                    m_playlistCurrentIndex = idx;
                }

                if (m_playlistCurrentIndex > 0) {
                    const QString title = p.at(2).trimmed();
                    if (!title.isEmpty())
                        emit playlistItemStarted(m_playlistCurrentIndex,
                                                 m_playlistTotalItems, title);

                    bool okPct = false, okTot = false, okEst = false,
                         okSpd = false, okEta = false, okDone = false, okApprox = false;
                    const double pct   = p.at(3).toDouble(&okPct);
                    const double total = p.at(4).toDouble(&okTot);
                    const double est   = p.at(5).toDouble(&okEst);
                    const double speed = p.at(6).toDouble(&okSpd);
                    const double etaS  = p.at(7).toDouble(&okEta);
                    const double done   = p.size() > 8 ? p.at(8).toDouble(&okDone)   : 0.0;
                    const double approx = p.size() > 9 ? p.at(9).toDouble(&okApprox) : 0.0;

                    const double percent = okPct ? qBound(0.0, pct, 100.0) : 0.0;
                    // YouTube DASH reports total_bytes/estimate as "NA" mid-fragment.
                    // Fall back to info.filesize_approx, then derive a total from the
                    // bytes downloaded so far divided by the percent complete.
                    qint64 totalBytes = okTot && total > 0 ? qint64(total)
                                      : (okEst && est > 0 ? qint64(est) : 0);
                    if (totalBytes <= 0 && okApprox && approx > 0)
                        totalBytes = qint64(approx);
                    if (totalBytes <= 0 && okDone && done > 0 && percent > 1.0) {
                        const double derived = done * 100.0 / percent;
                        // Cap the percent-derived total: a near-zero percent makes
                        // this explode, which later overflows int casts / formatters.
                        totalBytes = (std::isfinite(derived) && derived > 0
                                      && derived < 1.0e13) ? qint64(derived) : 0;
                    }
                    // yt-dlp eta is seconds; the UI formats "MM:SS"/"HH:MM:SS".
                    QString etaStr;
                    if (okEta && etaS > 0 && etaS < 100.0 * 3600.0) {
                        const int s = int(etaS);
                        etaStr = (s >= 3600)
                            ? QStringLiteral("%1:%2:%3").arg(s / 3600)
                                  .arg((s % 3600) / 60, 2, 10, QLatin1Char('0'))
                                  .arg(s % 60, 2, 10, QLatin1Char('0'))
                            : QStringLiteral("%1:%2").arg(s / 60)
                                  .arg(s % 60, 2, 10, QLatin1Char('0'));
                    }
                    emit playlistItemProgressData(m_playlistCurrentIndex, percent,
                                                  totalBytes,
                                                  okSpd ? sanitizeSpeed(qint64(speed)) : 0, etaStr);
                }
            }
            return;
        }

        // The console "Downloading item N of M" line carries the reliable total
        // count (and current index). It contains no title.
        static const QRegularExpression kItemRe(
            QStringLiteral(R"(\[download\]\s+Downloading item\s+(\d+)\s+of\s+(\d+))"),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch itemMatch = kItemRe.match(line);
        if (itemMatch.hasMatch()) {
            const int newIdx = itemMatch.captured(1).toInt();
            advancePlaylistItem(newIdx);
            m_playlistCurrentIndex = newIdx;
            m_playlistTotalItems = itemMatch.captured(2).toInt();
            qDebug() << "[YtdlpTransfer] downloading item" << m_playlistCurrentIndex
                     << "of" << m_playlistTotalItems;
            emit playlistItemStarted(m_playlistCurrentIndex, m_playlistTotalItems,
                                     QString());
        }
    }

    // ── Progress line ──────────────────────────────────────────────────────────
    if (tryParseProgressLine(line))
        return;

    // ── Destination announcement ──────────────────────────────────────────────
    // "[download] Destination: /path/to/My Video.mp4"
    // Capture the actual filename yt-dlp chose (may differ from our template
    // guess due to special character substitution).
    static const QLatin1String kDestPrefix("[download] Destination:");
    if (line.startsWith(kDestPrefix)) {
        const QString path = line.mid(kDestPrefix.size()).trimmed();
        const int sep = qMax(path.lastIndexOf(QLatin1Char('/')),
                             path.lastIndexOf(QLatin1Char('\\')));
        const QString filename = sanitizeFilename((sep >= 0) ? path.mid(sep + 1) : path);
        if (!filename.isEmpty()) {
            // In playlist mode the parent is a channel container whose name must
            // stay the channel title — the per-video filename feeds the child row
            // via playlistItemStarted instead of overwriting the container.
            if (!m_playlistMode)
                m_item->setFilename(filename);
            // Playlist mode: display name stays the clean title (set via STPROG);
            // carry the real on-disk filename separately for open/reveal.
            if (m_playlistMode && m_playlistCurrentIndex > 0)
                emit playlistItemFilePath(m_playlistCurrentIndex, filename);
        }
        return;
    }

    // ── Already downloaded ────────────────────────────────────────────────────
    // Line format: "[download] Video Title.mp4 has already been downloaded"
    // There is no Destination: line in this case, so we extract the filename here.
    static const QLatin1String kAlreadyDl("has already been downloaded");
    if (line.contains(QStringLiteral("[download]")) && line.contains(kAlreadyDl)) {
        const int prefixEnd = line.indexOf(QLatin1Char(']')) + 2; // skip "[download] "
        const int suffixStart = line.indexOf(kAlreadyDl);
        if (prefixEnd > 1 && suffixStart > prefixEnd) {
            const QString name = line.mid(prefixEnd, suffixStart - prefixEnd).trimmed();
            // name may be a bare filename or a full path depending on yt-dlp version
            const int sep = qMax(name.lastIndexOf(QLatin1Char('/')),
                                 name.lastIndexOf(QLatin1Char('\\')));
            const QString filename = sanitizeFilename((sep >= 0) ? name.mid(sep + 1) : name);
            if (!filename.isEmpty()) {
                if (!m_playlistMode)
                    m_item->setFilename(filename);
                if (m_playlistMode && m_playlistCurrentIndex > 0) {
                    emit playlistItemFilePath(m_playlistCurrentIndex, filename);
                    emit playlistItemProgress(m_playlistCurrentIndex, 100.0);
                    emit playlistItemFinished(m_playlistCurrentIndex);
                }
            }
        }
        if (m_item->totalBytes() > 0)
            m_item->setDoneBytes(m_item->totalBytes());
        return;
    }

    // ── Merger / ffmpeg phase ─────────────────────────────────────────────────
    // Video and audio streams are merged by ffmpeg after both are downloaded.
    // Show "Assembling..." in the status bar during this phase.
    // The merger line announces the final output path:
    //   [Merger] Merging formats into "/path/to/Video Title.mp4"
    // Capture this to update the filename from .webm → .mp4 (or whatever container).
    if (line.startsWith(QStringLiteral("[Merger]")) ||
        line.startsWith(QStringLiteral("[ffmpeg]"))) {
        // In playlist mode m_item is the container — keep its aggregate status; the
        // merge belongs to a single child, not the whole channel.
        if (!m_playlistMode) {
            m_item->setStatus(DownloadItem::Status::Assembling);
            m_item->setSpeed(0);
        }

        // "[Merger] Merging formats into "…path…""
        const int quoteOpen  = line.indexOf(QLatin1Char('"'));
        const int quoteClose = line.lastIndexOf(QLatin1Char('"'));
        if (quoteOpen >= 0 && quoteClose > quoteOpen) {
            const QString path = line.mid(quoteOpen + 1, quoteClose - quoteOpen - 1);
            const int sep = qMax(path.lastIndexOf(QLatin1Char('/')),
                                 path.lastIndexOf(QLatin1Char('\\')));
            const QString filename = sanitizeFilename((sep >= 0) ? path.mid(sep + 1) : path);
            if (!filename.isEmpty()) {
                if (!m_playlistMode)
                    m_item->setFilename(filename);
                if (m_playlistMode && m_playlistCurrentIndex > 0)
                    emit playlistItemFilePath(m_playlistCurrentIndex, filename);
            }
        }

        qDebug() << "[YtdlpTransfer] merging:" << line;
        return;
    }

    qDebug() << "[yt-dlp]" << line;
    // Bound the captured-output buffer: a long playlist or a chatty/hostile
    // process could otherwise grow m_allLines without limit. Only the tail is
    // used for the failure message, so keep the most recent lines.
    static constexpr int kMaxCapturedLines = 200;
    m_allLines.append(line);
    if (m_allLines.size() > kMaxCapturedLines)
        m_allLines.remove(0, m_allLines.size() - kMaxCapturedLines);
}

bool YtdlpTransfer::tryParseProgressLine(const QString &line) {
    // Expected format (with --newline):
    //   [download]  45.3% of    1.00GiB at    2.53MiB/s ETA 06:30
    //   [download]  45.3% of ~  1.00GiB at    2.53MiB/s ETA 06:30  (approx)
    //   [download] 100% of    1.00GiB at    8.00MiB/s ETA 00:00
    //
    // Regex captures: percent, total value, total unit, speed value, speed unit.
    // The tilde (~) for approximate totals is optional.

    if (!line.startsWith(QStringLiteral("[download]")))
        return false;

    static const QRegularExpression kProgressRe(
        QStringLiteral(
            R"(\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+)\s*([A-Za-z]+)\s+at\s+~?\s*([\d.]+)\s*([A-Za-z]+)/s(?:\s+ETA\s+(\S+))?)"
        ),
        QRegularExpression::CaseInsensitiveOption);

    const QRegularExpressionMatch m = kProgressRe.match(line);
    if (!m.hasMatch())
        return false;

    const double  pct        = m.captured(1).toDouble();
    const double  totalVal   = m.captured(2).toDouble();
    const QString totalUnit  = m.captured(3);
    const double  speedVal   = m.captured(4).toDouble();
    const QString speedUnit  = m.captured(5);
    const QString eta        = m.captured(6);

    const qint64 phaseTotal = parseSizeToBytes(totalVal, totalUnit);
    const qint64 speedBps   = sanitizeSpeed(parseSizeToBytes(speedVal, speedUnit));
    const qint64 phaseDone  = (phaseTotal > 0)
        ? static_cast<qint64>(phaseTotal * pct / 100.0)
        : 0;

    // ── Phase-transition detection ────────────────────────────────────────────
    // When the percentage drops from >90 % to <10 %, a new download phase has
    // started (e.g., audio track following the video track).  Accumulate the
    // completed phase's total bytes.
    if (m_seenFullPhase && pct < 10.0 && m_lastPercent > 90.0) {
        m_accumulatedBytes += m_currentPhaseTotal;
        m_currentPhaseDone  = 0;
        m_currentPhaseTotal = 0;
    }

    // Mark that we've seen at least one complete phase
    if (pct >= 99.5)
        m_seenFullPhase = true;

    m_lastPercent = pct;

    // Update running phase tracking (keep the largest total seen — it can grow
    // as yt-dlp refines its estimate).
    if (phaseTotal > m_currentPhaseTotal)
        m_currentPhaseTotal = phaseTotal;
    m_currentPhaseDone = phaseDone;

    // ── Overall progress ──────────────────────────────────────────────────────
    const qint64 overallDone  = m_accumulatedBytes + m_currentPhaseDone;
    const qint64 overallTotal = m_accumulatedBytes + m_currentPhaseTotal;

    // In playlist mode m_item is the channel *container*; its bytes/speed/status are
    // the aggregate over all videos, owned by AppController::recomputeChannelAggregate.
    // Writing single-phase numbers here would stomp that aggregate (the original
    // "parent shows current video % / 0.0%" bug). Per-video stats flow via the
    // playlistItem* signals below instead.
    if (!m_playlistMode) {
        m_item->setTotalBytes(overallTotal);
        m_item->setDoneBytes(overallDone);
        m_item->setSpeed(speedBps);

        // Restore Downloading status if a previous Assembling marker was set for
        // a different stream in a multi-pass download.
        if (m_item->statusEnum() == DownloadItem::Status::Assembling)
            m_item->setStatus(DownloadItem::Status::Downloading);
    }

    emit progressChanged(overallDone, overallTotal, speedBps);
    if (m_playlistMode && m_playlistCurrentIndex > 0) {
        emit playlistItemProgress(m_playlistCurrentIndex, pct);
        emit playlistItemProgressData(m_playlistCurrentIndex, pct, phaseTotal,
                                      speedBps, eta);
        if (pct >= 99.5)
            emit playlistItemFinished(m_playlistCurrentIndex);
    }
    return true;
}

// ── Process lifecycle slots ───────────────────────────────────────────────────

void YtdlpTransfer::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    if (m_aborted) return;

    // Flush any remaining buffered data before interpreting the exit code.
    if (m_process) {
        m_lineBuf += m_process->readAllStandardOutput();
        int nl;
        while ((nl = m_lineBuf.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(m_lineBuf.left(nl)).trimmed();
            m_lineBuf.remove(0, nl + 1);
            if (!line.isEmpty()) handleLine(line);
        }
    }

    m_item->setSpeed(0);
    m_item->setResumeCapable(true);

    if (exitCode == 0 && exitStatus == QProcess::NormalExit) {
        // Clamp doneBytes to totalBytes so progress shows exactly 100 %. In playlist
        // mode the container's 100% is set by recomputeChannelAggregate once every
        // child is finished (below) — don't stomp the aggregate here.
        if (!m_playlistMode && m_item->totalBytes() > 0)
            m_item->setDoneBytes(m_item->totalBytes());

        // Clean exit = the whole playlist downloaded. Finalise EVERY item, not just
        // from m_playlistStartedIndex: yt-dlp can finish items out of order (or skip
        // the final 100% tick), leaving an earlier item stuck at 99% forever. The
        // emits are idempotent — already-completed rows stay completed.
        if (m_playlistMode) {
            const int last = qMax(qMax(m_playlistCurrentIndex, m_playlistStartedIndex),
                                  m_playlistTotalItems);
            for (int done = 1; done <= last; ++done) {
                emit playlistItemProgress(done, 100.0);
                emit playlistItemFinished(done);
            }
        }

        // ── Filesystem filename reconciliation ───────────────────────────────
        // The filename we store comes from parsing "[download] Destination:" or
        // "[Merger] Merging formats into" lines in yt-dlp's stdout.  On Windows,
        // even with PYTHONUTF8=1 and PYTHONIOENCODING=utf-8 set, some yt-dlp
        // builds output those lines in the system codepage (e.g. CP1252) rather
        // than UTF-8.  Characters like en-dash (U+2013, 0xE2 0x80 0x93 in UTF-8,
        // but 0x96 in CP1252) then decode to U+FFFD (replacement character) when
        // we call QString::fromUtf8().  The corrupted filename doesn't match the
        // real file on disk, so "Open File" / "Open Folder" silently fail.
        //
        // Fix: after a successful download, verify the path exists.  If it doesn't,
        // scan the save directory for the newest file — Qt's QDir uses Windows
        // native Unicode APIs (FindFirstFileW) to read directory entries, so the
        // filename it returns is always correct regardless of stdout encoding.
        // Skip for playlist containers: their name is the channel title, and there
        // are many output files (one per video) — there's no single name to
        // reconcile. Per-video filenames live on the child rows instead.
        if (!m_playlistMode) {
            const QString storedPath = m_saveDir + QLatin1Char('/') + m_item->filename();
            if (m_item->filename().isEmpty() || !QFile::exists(storedPath)) {
                // Stdout-derived filename is missing or doesn't match any real file
                // (common on Windows when yt-dlp emits the path in the system
                // codepage instead of UTF-8, corrupting non-ASCII characters).
                //
                // Use the pre-launch directory snapshot to restrict candidates to
                // files that are attributable to THIS transfer:
                //   - Brand-new files (not present in the snapshot at all), OR
                //   - Files that grew since launch (a resumed partial file).
                // Among those, prefer files whose extension matches the requested
                // container format, then fall back to the most-recently-modified
                // candidate.  This avoids claiming an unrelated file from a busy
                // shared save folder.
                const QString wantedExt = m_containerFormat.toLower();
                const QFileInfoList all = QDir(m_saveDir).entryInfoList(
                    QDir::Files | QDir::NoDotAndDotDot, QDir::Time);

                QFileInfo bestMatch;
                for (const QFileInfo &fi : all) {
                    const QString name = fi.fileName();
                    // Skip .part/.stellar-* temporary files — yt-dlp may leave
                    // these if a previous attempt was interrupted.
                    if (name.endsWith(QStringLiteral(".part"), Qt::CaseInsensitive) ||
                        name.contains(QStringLiteral(".stellar-")))
                        continue;

                    const bool isNew     = !m_preLaunchSnapshot.contains(name);
                    const bool isGrown   = !isNew &&
                        fi.size() > m_preLaunchSnapshot.value(name, fi.size());

                    if (!isNew && !isGrown)
                        continue; // pre-existing file unchanged — not ours

                    // First qualifying candidate wins unless a later one has a
                    // better extension match.  The list is already sorted newest-
                    // first (QDir::Time), so within the same extension tier the
                    // most recently modified file is chosen automatically.
                    if (bestMatch.fileName().isEmpty()) {
                        bestMatch = fi;
                    } else {
                        const bool curHasExt  = bestMatch.suffix().toLower() == wantedExt;
                        const bool candHasExt = fi.suffix().toLower() == wantedExt;
                        if (candHasExt && !curHasExt)
                            bestMatch = fi; // upgrade to a better extension match
                    }
                }

                if (!bestMatch.fileName().isEmpty()) {
                    qDebug() << "[YtdlpTransfer] filename reconciled via snapshot:"
                             << bestMatch.fileName();
                    m_item->setFilename(bestMatch.fileName());
                } else {
                    qWarning() << "[YtdlpTransfer] could not reconcile filename in"
                               << m_saveDir;
                }
            }
        }

        m_item->setStatus(DownloadItem::Status::Completed);
        emit finished();
    } else {
        // Build error detail from all accumulated non-progress output lines.
        // This captures ERROR: messages, network errors, unsupported-URL notices, etc.
        const QString reason = m_allLines.isEmpty()
            ? QStringLiteral("yt-dlp exited with code %1").arg(exitCode)
            : m_allLines.join(QLatin1Char('\n'));
        m_item->setStatus(DownloadItem::Status::Error);
        emit failed(reason);
    }
}

void YtdlpTransfer::onProcessError(QProcess::ProcessError err) {
    if (m_aborted) return;
    Q_UNUSED(err)

    m_item->setSpeed(0);
    m_item->setStatus(DownloadItem::Status::Error);

    const QString reason = (m_process && !m_process->errorString().isEmpty())
        ? m_process->errorString()
        : QStringLiteral("Failed to start yt-dlp. Please check your installation.");
    emit failed(reason);
}

// ── Unit conversion ───────────────────────────────────────────────────────────

qint64 YtdlpTransfer::parseSizeToBytes(double value, const QString &unit) {
    // Converting an out-of-range or non-finite double to qint64 is undefined
    // behaviour. yt-dlp progress lines are untrusted text, so a crafted/garbled
    // unit+value could otherwise UB-crash here. Clamp every result to [0, max].
    auto toBytes = [](double bytes) -> qint64 {
        if (!std::isfinite(bytes) || bytes <= 0.0)
            return 0;
        constexpr double kMax = 9.2e18; // < INT64_MAX, safe to cast
        if (bytes >= kMax)
            return std::numeric_limits<qint64>::max();
        return static_cast<qint64>(bytes);
    };

    const QString u = unit.toLower();
    // IEC binary prefixes (yt-dlp default)
    if (u == QStringLiteral("tib")) return toBytes(value * 1099511627776.0);
    if (u == QStringLiteral("gib")) return toBytes(value * 1073741824.0);
    if (u == QStringLiteral("mib")) return toBytes(value * 1048576.0);
    if (u == QStringLiteral("kib")) return toBytes(value * 1024.0);
    if (u == QStringLiteral("b"))   return toBytes(value);
    // SI decimal prefixes (fallback)
    if (u == QStringLiteral("tb"))  return toBytes(value * 1000000000000.0);
    if (u == QStringLiteral("gb"))  return toBytes(value * 1000000000.0);
    if (u == QStringLiteral("mb"))  return toBytes(value * 1000000.0);
    if (u == QStringLiteral("kb"))  return toBytes(value * 1000.0);
    // Unknown unit — treat value as raw bytes
    return toBytes(value);
}
