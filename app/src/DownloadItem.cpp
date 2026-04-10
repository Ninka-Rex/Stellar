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
    case Status::Downloading: return QStringLiteral("Downloading");
    case Status::Paused:      return QStringLiteral("Paused");
    case Status::Assembling:  return QStringLiteral("Assembling...");
    case Status::Completed:   return QStringLiteral("Completed");
    case Status::Error:       return QStringLiteral("Error");
    }
    return QStringLiteral("Unknown");
}

QString DownloadItem::timeLeft() const {
    if (m_speed <= 0 || m_totalBytes <= 0) return {};
    qint64 remaining = (m_totalBytes - m_doneBytes) / m_speed;
    if (remaining < 60)   return QStringLiteral("%1 sec").arg(remaining);
    if (remaining < 3600) return QStringLiteral("%1 min %2 sec").arg(remaining/60).arg(remaining%60);
    const qint64 h = remaining / 3600, m = (remaining % 3600) / 60;
    return m > 0 ? QStringLiteral("%1 hour%2 %3 min").arg(h).arg(h > 1 ? "s" : "").arg(m)
                 : QStringLiteral("%1 hour%2").arg(h).arg(h > 1 ? "s" : "");
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
void DownloadItem::setStatus(Status s)                  { if (m_status        != s) { m_status        = s; emit statusChanged();         } }
void DownloadItem::setCategory(const QString &v)        { if (m_category      != v) { m_category      = v; emit categoryChanged();       } }
void DownloadItem::setSavePath(const QString &v)        { if (m_savePath      != v) { m_savePath      = v; emit savePathChanged();       } }
void DownloadItem::setResumeCapable(bool v)             { if (m_resumeCapable != v) { m_resumeCapable = v; emit resumeCapableChanged();  } }
void DownloadItem::setSegmentData(const QVariantList &v){ if (m_segmentData   != v) { m_segmentData   = v; emit segmentDataChanged();    } }
void DownloadItem::setDescription(const QString &v)     { if (m_description   != v) { m_description   = v; emit descriptionChanged();    } }
void DownloadItem::setSpeedLimitKBps(int v)             { if (m_speedLimitKBps != v) { m_speedLimitKBps = v; emit speedLimitKBpsChanged(v); } }
