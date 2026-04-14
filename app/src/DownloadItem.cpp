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

#include "DownloadItem.h"
#include <QFileInfo>

int DownloadItem::s_dateStyle = 0;
bool DownloadItem::s_use24Hour = true;
bool DownloadItem::s_showSeconds = true;

DownloadItem::DownloadItem(const QString &id, const QUrl &url, QObject *parent)
    : QObject(parent), m_id(id), m_url(url), m_addedAt(QDateTime::currentDateTime())
{
    m_filename = QFileInfo(url.path()).fileName();
    if (m_filename.isEmpty())
        m_filename = QStringLiteral("download");
}

void DownloadItem::configureDateTimeFormat(int dateStyle, bool use24Hour, bool showSeconds) {
    s_dateStyle = dateStyle;
    s_use24Hour = use24Hour;
    s_showSeconds = showSeconds;
}

double DownloadItem::progress() const {
    if (m_totalBytes <= 0) return 0.0;
    return static_cast<double>(m_doneBytes) / m_totalBytes;
}

QString DownloadItem::status() const {
    switch (m_status) {
    case Status::Queued:      return QStringLiteral("Queued");
    case Status::Checking:    return QStringLiteral("Checking");
    case Status::Downloading: return QStringLiteral("Downloading");
    case Status::Moving:      return QStringLiteral("Moving");
    case Status::Seeding:     return QStringLiteral("Seeding");
    case Status::Paused:      return QStringLiteral("Paused");
    case Status::Assembling:  return QStringLiteral("Assembling...");
    case Status::Completed:   return QStringLiteral("Completed");
    case Status::Error:       return QStringLiteral("Error");
    }
    return QStringLiteral("Unknown");
}

QString DownloadItem::timeLeft() const {
    if (m_status == Status::Paused || m_status == Status::Checking || m_status == Status::Moving
        || m_status == Status::Completed || m_status == Status::Error)
        return {};
    // Use the longer-window ETA speed when available; fall back to display speed.
    qint64 speedForEta = m_etaSpeed > 0 ? m_etaSpeed : m_speed;
    if (speedForEta <= 0 || m_totalBytes <= 0) return {};
    qint64 remaining = (m_totalBytes - m_doneBytes) / speedForEta;
    if (remaining < 60) return QStringLiteral("%1 sec").arg(remaining);

    struct Unit {
        qint64 seconds;
        const char *singular;
        const char *plural;
    };

    static const Unit units[] = {
        { 31557600000ll, "millennium", "millennia" },
        { 3155760000ll,  "century", "centuries" },
        { 315576000ll,   "decade", "decades" },
        { 31557600ll,    "year", "years" },
        { 2629800ll,     "month", "months" },
        { 86400ll,       "day", "days" },
        { 3600ll,        "hour", "hours" },
        { 60ll,          "min", "min" }
    };

    QStringList parts;
    qint64 remainder = remaining;
    for (const Unit &unit : units) {
        if (remainder < unit.seconds)
            continue;
        const qint64 count = remainder / unit.seconds;
        remainder %= unit.seconds;
        parts.push_back(QStringLiteral("%1 %2").arg(count).arg(count == 1 ? unit.singular : unit.plural));
        if (parts.size() == 2)
            break;
    }

    if (parts.isEmpty())
        return QStringLiteral("%1 min").arg((remaining + 59) / 60);
    return parts.join(QLatin1Char(' '));
}

QString DownloadItem::addedDateStr() const {
    const QDateTime &d = (m_lastTryAt.isValid() && m_lastTryAt.toMSecsSinceEpoch() > 0)
        ? m_lastTryAt : m_addedAt;
    return d.isValid() ? formatDateTime(d) : QString();
}

QString DownloadItem::lastTryDateStr() const {
    return (m_lastTryAt.isValid() && m_lastTryAt.toMSecsSinceEpoch() > 0)
        ? formatDateTime(m_lastTryAt)
        : QStringLiteral("--");
}

QString DownloadItem::formatDateTime(const QDateTime &dt) {
    if (!dt.isValid())
        return QString();

    QString dateFormat;
    switch (s_dateStyle) {
    case 1:
        dateFormat = QStringLiteral("M/d/yyyy");
        break;
    case 2:
        dateFormat = QStringLiteral("d/M/yyyy");
        break;
    case 3:
        dateFormat = QStringLiteral("yyyy-MM-dd");
        break;
    case 0:
    default:
        dateFormat = QStringLiteral("MMM d yyyy");
        break;
    }

    QString timeFormat;
    if (s_use24Hour)
        timeFormat = s_showSeconds ? QStringLiteral("HH:mm:ss") : QStringLiteral("HH:mm");
    else
        timeFormat = s_showSeconds ? QStringLiteral("h:mm:ss AP") : QStringLiteral("h:mm AP");

    return dt.toString(dateFormat + QStringLiteral(" ") + timeFormat);
}

void DownloadItem::setFilename(const QString &v)       { if (m_filename      != v) { m_filename      = v; emit filenameChanged();      } }
void DownloadItem::setTotalBytes(qint64 v)              { if (m_totalBytes    != v) { m_totalBytes    = v; emit totalBytesChanged();     } }
void DownloadItem::setDoneBytes(qint64 v)               { if (m_doneBytes     != v) { m_doneBytes     = v; emit doneBytesChanged(); emit timeLeftChanged(); } }
void DownloadItem::setSpeed(qint64 bytesPerSec)         { if (m_speed         != bytesPerSec) { m_speed = bytesPerSec; emit speedChanged(); emit timeLeftChanged(); } }
void DownloadItem::setEtaSpeed(qint64 bytesPerSec)      { m_etaSpeed = bytesPerSec; emit timeLeftChanged(); }
void DownloadItem::setStatus(Status s)                  { if (m_status        != s) { m_status        = s; emit statusChanged(); emit timeLeftChanged(); } }
void DownloadItem::setCategory(const QString &v)        { if (m_category      != v) { m_category      = v; emit categoryChanged();       } }
void DownloadItem::setSavePath(const QString &v)        { if (m_savePath      != v) { m_savePath      = v; emit savePathChanged();       } }
void DownloadItem::setResumeCapable(bool v)             { if (m_resumeCapable != v) { m_resumeCapable = v; emit resumeCapableChanged();  } }
void DownloadItem::setSegmentData(const QVariantList &v){ if (m_segmentData   != v) { m_segmentData   = v; emit segmentDataChanged();    } }
void DownloadItem::setDescription(const QString &v)     { if (m_description   != v) { m_description   = v; emit descriptionChanged();    } }
void DownloadItem::setSpeedLimitKBps(int v)             { if (m_speedLimitKBps != v) { m_speedLimitKBps = v; emit speedLimitKBpsChanged(v); } }
void DownloadItem::setIsTorrent(bool v)                 { if (m_isTorrent != v) { m_isTorrent = v; emit torrentChanged(); } }
void DownloadItem::setTorrentSource(const QString &v)   { if (m_torrentSource != v) { m_torrentSource = v; emit torrentChanged(); } }
void DownloadItem::setTorrentInfoHash(const QString &v) { if (m_torrentInfoHash != v) { m_torrentInfoHash = v; emit torrentChanged(); } }
void DownloadItem::setTorrentSeeders(int v)             { if (m_torrentSeeders != v) { m_torrentSeeders = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentPeers(int v)               { if (m_torrentPeers != v) { m_torrentPeers = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentRatio(double v)            { if (!qFuzzyCompare(m_torrentRatio + 1.0, v + 1.0)) { m_torrentRatio = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentUploaded(qint64 v)         { if (m_torrentUploaded != v) { m_torrentUploaded = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentDownloaded(qint64 v)       { if (m_torrentDownloaded != v) { m_torrentDownloaded = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentUploadSpeed(qint64 v)      { if (m_torrentUploadSpeed != v) { m_torrentUploadSpeed = v; emit torrentStatsChanged(); } }
void DownloadItem::setTorrentHasMetadata(bool v)        { if (m_torrentHasMetadata != v) { m_torrentHasMetadata = v; emit torrentChanged(); } }
void DownloadItem::setTorrentResumeData(const QString &v) { if (m_torrentResumeData != v) { m_torrentResumeData = v; emit torrentChanged(); } }

void DownloadItem::clearTorrentStats() {
    bool changed = false;
    if (m_torrentSeeders != 0)          { m_torrentSeeders = 0;          changed = true; }
    if (m_torrentListSeeders != 0)      { m_torrentListSeeders = 0;      changed = true; }
    if (m_torrentPeers != 0)            { m_torrentPeers = 0;            changed = true; }
    if (m_torrentListPeers != 0)        { m_torrentListPeers = 0;        changed = true; }
    if (!qFuzzyIsNull(m_torrentRatio))  { m_torrentRatio = 0.0;          changed = true; }
    if (m_torrentUploaded != 0)         { m_torrentUploaded = 0;         changed = true; }
    if (m_torrentDownloaded != 0)       { m_torrentDownloaded = 0;       changed = true; }
    if (m_torrentUploadSpeed != 0)      { m_torrentUploadSpeed = 0;      changed = true; }
    if (m_torrentAvailability != 0.f)   { m_torrentAvailability = 0.f;   changed = true; }
    if (m_torrentPiecesDone != 0)       { m_torrentPiecesDone = 0;       changed = true; }
    if (m_torrentPiecesTotal != 0)      { m_torrentPiecesTotal = 0;      changed = true; }
    if (m_torrentActiveTimeSecs != 0)   { m_torrentActiveTimeSecs = 0;   changed = true; }
    if (m_torrentSeedingTimeSecs != 0)  { m_torrentSeedingTimeSecs = 0;  changed = true; }
    if (m_torrentWastedBytes != 0)      { m_torrentWastedBytes = 0;      changed = true; }
    if (m_torrentConnections != 0)      { m_torrentConnections = 0;      changed = true; }
    if (changed)
        emit torrentStatsChanged();
}
