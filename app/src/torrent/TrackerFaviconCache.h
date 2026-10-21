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

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QQueue>
#include <QSet>
#include <QString>
#include <QStringList>

class AppSettings;
class QNetworkAccessManager;
class QNetworkReply;

// Tracker website favicons for the Trackers tab, cached on disk as 32px PNGs
// in StellarPaths::trackerIconCacheDir(). Opt-in (torrentTrackerFavicons):
// fetching contacts the tracker's web host directly, outside any torrent
// interface binding.
//
// QML calls iconFor(trackerUrl), which answers from the cache immediately and
// otherwise queues a background fetch; bind on `revision` to pick the icon up
// once it lands. Lives on the GUI thread (owns network replies).
class TrackerFaviconCache : public QObject {
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
public:
    TrackerFaviconCache(QNetworkAccessManager *nam, AppSettings *settings, QObject *parent = nullptr);

    // file:// URL of the cached icon for the tracker's host, or "" (not cached
    // yet, fetch failed, feature off, or not a web-reachable host).
    Q_INVOKABLE QString iconFor(const QString &trackerUrl);
    int revision() const { return m_revision; }

signals:
    void revisionChanged();

private:
    struct Job {
        QString host;
        QStringList candidates;   // favicon URLs, tried in order
    };

    // Lower-cased DNS name / IPv4 of a tracker URL, or "" if unusable. The
    // allowed charset ([a-z0-9.-]) makes it safe to use as a file name.
    static QString hostOf(const QString &trackerUrl);
    QString iconPath(const QString &host) const;
    QString missPath(const QString &host) const;
    void startNext();
    void tryCandidate(Job job);
    void finishJob(const QString &host, bool success);

    QNetworkAccessManager *m_nam;
    AppSettings *m_settings;
    QString m_dir;
    QHash<QString, QString> m_known;     // host -> icon URL ("" = known miss)
    QSet<QString> m_pending;             // queued or in flight
    QQueue<Job> m_queue;
    int m_active{0};
    int m_revision{0};
};
