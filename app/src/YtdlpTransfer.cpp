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
#include <QRegularExpression>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>

// ── Constructor / Destructor ──────────────────────────────────────────────────

YtdlpTransfer::YtdlpTransfer(DownloadItem *item,
                              const QString &ytdlpPath,
                              const QString &formatSel,
                              const QString &containerFormat,
                              const QString &saveDir,
                              const QString &ffmpegPath,
                              bool           resume,
                              const QString &outputTemplate,
                              const QString &proxyUrl,
                              QObject       *parent)
    : QObject(parent)
    , m_item(item)
    , m_ytdlpPath(ytdlpPath)
    , m_formatSel(formatSel)
    , m_containerFormat(containerFormat.isEmpty() ? QStringLiteral("mp4") : containerFormat)
    , m_saveDir(saveDir)
    , m_ffmpegPath(ffmpegPath)
    , m_resume(resume)
    , m_outputTemplate(outputTemplate.isEmpty() ? QStringLiteral("%(title)s.%(ext)s") : outputTemplate)
    , m_proxyUrl(proxyUrl)
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
    args << QStringLiteral("--no-playlist")
         << QStringLiteral("--newline")
         << QStringLiteral("--no-warnings")
         << QStringLiteral("-f")  << m_formatSel;

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

    if (m_resume)
        args << QStringLiteral("--continue");

    // yt-dlp does not inherit Qt's application-level proxy — it must be told explicitly.
    // Pass an empty string to "--proxy" to force yt-dlp to use NO proxy (overrides
    // any system proxy that might otherwise be picked up from environment variables).
    if (!m_proxyUrl.isEmpty())
        args << QStringLiteral("--proxy") << m_proxyUrl;
    else
        args << QStringLiteral("--proxy") << QStringLiteral("");  // explicit "no proxy"

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
    m_item->setStatus(DownloadItem::Status::Downloading);
    m_item->setResumeCapable(true);

    m_process->start();
    emit started();
    qDebug() << "[YtdlpTransfer] started:" << m_ytdlpPath << args;
}

void YtdlpTransfer::pause() {
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->kill();
        m_process->waitForFinished(3000);
        m_process->deleteLater();
        m_process = nullptr;
    }
    m_item->setStatus(DownloadItem::Status::Paused);
    m_item->setSpeed(0);
}

void YtdlpTransfer::abort() {
    m_aborted = true;
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->kill();
        m_process->waitForFinished(3000);
        m_process->deleteLater();
        m_process = nullptr;
    }
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

void YtdlpTransfer::handleLine(const QString &line) {
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
        if (sep >= 0) {
            const QString filename = path.mid(sep + 1);
            if (!filename.isEmpty())
                m_item->setFilename(filename);
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
            const QString filename = (sep >= 0) ? name.mid(sep + 1) : name;
            if (!filename.isEmpty())
                m_item->setFilename(filename);
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
        m_item->setStatus(DownloadItem::Status::Assembling);
        m_item->setSpeed(0);

        // "[Merger] Merging formats into "…path…""
        const int quoteOpen  = line.indexOf(QLatin1Char('"'));
        const int quoteClose = line.lastIndexOf(QLatin1Char('"'));
        if (quoteOpen >= 0 && quoteClose > quoteOpen) {
            const QString path = line.mid(quoteOpen + 1, quoteClose - quoteOpen - 1);
            const int sep = qMax(path.lastIndexOf(QLatin1Char('/')),
                                 path.lastIndexOf(QLatin1Char('\\')));
            const QString filename = (sep >= 0) ? path.mid(sep + 1) : path;
            if (!filename.isEmpty())
                m_item->setFilename(filename);
        }

        qDebug() << "[YtdlpTransfer] merging:" << line;
        return;
    }

    qDebug() << "[yt-dlp]" << line;
    m_allLines.append(line);
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
            R"(\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+)\s*([A-Za-z]+)\s+at\s+~?\s*([\d.]+)\s*([A-Za-z]+)/s)"
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

    const qint64 phaseTotal = parseSizeToBytes(totalVal, totalUnit);
    const qint64 speedBps   = parseSizeToBytes(speedVal, speedUnit);
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

    m_item->setTotalBytes(overallTotal);
    m_item->setDoneBytes(overallDone);
    m_item->setSpeed(speedBps);

    // Restore Downloading status if a previous Assembling marker was set for
    // a different stream in a multi-pass download.
    if (m_item->statusEnum() == DownloadItem::Status::Assembling)
        m_item->setStatus(DownloadItem::Status::Downloading);

    emit progressChanged(overallDone, overallTotal, speedBps);
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
        // Clamp doneBytes to totalBytes so progress shows exactly 100 %
        if (m_item->totalBytes() > 0)
            m_item->setDoneBytes(m_item->totalBytes());

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
        {
            const QString storedPath = m_saveDir + QLatin1Char('/') + m_item->filename();
            if (m_item->filename().isEmpty() || !QFile::exists(storedPath)) {
                QDir dir(m_saveDir);
                const QFileInfoList files = dir.entryInfoList(
                    QDir::Files | QDir::NoDotAndDotDot, QDir::Time);
                if (!files.isEmpty())
                    m_item->setFilename(files.first().fileName());
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
    const QString u = unit.toLower();
    // IEC binary prefixes (yt-dlp default)
    if (u == QStringLiteral("tib")) return static_cast<qint64>(value * 1099511627776.0);
    if (u == QStringLiteral("gib")) return static_cast<qint64>(value * 1073741824.0);
    if (u == QStringLiteral("mib")) return static_cast<qint64>(value * 1048576.0);
    if (u == QStringLiteral("kib")) return static_cast<qint64>(value * 1024.0);
    if (u == QStringLiteral("b"))   return static_cast<qint64>(value);
    // SI decimal prefixes (fallback)
    if (u == QStringLiteral("tb"))  return static_cast<qint64>(value * 1000000000000.0);
    if (u == QStringLiteral("gb"))  return static_cast<qint64>(value * 1000000000.0);
    if (u == QStringLiteral("mb"))  return static_cast<qint64>(value * 1000000.0);
    if (u == QStringLiteral("kb"))  return static_cast<qint64>(value * 1000.0);
    // Unknown unit — treat value as raw bytes
    return static_cast<qint64>(value);
}
