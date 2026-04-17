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
#include <QString>
#include <QUrl>
#include <QDateTime>
#include <QVariantList>
#include <QStringList>

class DownloadItem : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString  id             READ id             CONSTANT)
    Q_PROPERTY(QString  filename       READ filename       NOTIFY filenameChanged)
    Q_PROPERTY(QUrl     url            READ url            CONSTANT)
    Q_PROPERTY(qint64   totalBytes     READ totalBytes     NOTIFY totalBytesChanged)
    Q_PROPERTY(qint64   doneBytes      READ doneBytes      NOTIFY doneBytesChanged)
    Q_PROPERTY(double   progress       READ progress       NOTIFY doneBytesChanged)
    Q_PROPERTY(qint64   speed          READ speed          NOTIFY speedChanged)
    Q_PROPERTY(QString  status         READ status         NOTIFY statusChanged)
    Q_PROPERTY(QString  category       READ category       NOTIFY categoryChanged)
    Q_PROPERTY(QString  savePath       READ savePath       NOTIFY savePathChanged)
    Q_PROPERTY(QDateTime addedAt       READ addedAt        CONSTANT)
    Q_PROPERTY(QString  timeLeft       READ timeLeft       NOTIFY timeLeftChanged)
    Q_PROPERTY(bool     resumeCapable  READ resumeCapable  NOTIFY resumeCapableChanged)
    Q_PROPERTY(QVariantList segmentData READ segmentData   NOTIFY segmentDataChanged)
    Q_PROPERTY(QString  description    READ description    NOTIFY descriptionChanged)
    Q_PROPERTY(int      speedLimitKBps READ speedLimitKBps WRITE setSpeedLimitKBps NOTIFY speedLimitKBpsChanged)
    Q_PROPERTY(QString  errorString    READ errorString    NOTIFY errorStringChanged)
    Q_PROPERTY(QString  queueId        READ queueId        WRITE setQueueId NOTIFY queueIdChanged)
    Q_PROPERTY(QString  referrer       READ referrer       NOTIFY referrerChanged)
    Q_PROPERTY(QString  parentUrl      READ parentUrl      NOTIFY parentUrlChanged)
    Q_PROPERTY(QString  username       READ username       NOTIFY usernameChanged)
    Q_PROPERTY(QString  password       READ password       NOTIFY passwordChanged)
    Q_PROPERTY(QDateTime lastTryAt     READ lastTryAt      NOTIFY lastTryAtChanged)
    Q_PROPERTY(QString  addedDateStr  READ addedDateStr   NOTIFY lastTryAtChanged)
    Q_PROPERTY(QString  lastTryDateStr READ lastTryDateStr NOTIFY lastTryAtChanged)
    Q_PROPERTY(bool     isTorrent     READ isTorrent      NOTIFY torrentChanged)
    Q_PROPERTY(QString  torrentSource READ torrentSource  NOTIFY torrentChanged)
    Q_PROPERTY(QStringList torrentTrackers READ torrentTrackers NOTIFY torrentChanged)
    Q_PROPERTY(QString  torrentInfoHash READ torrentInfoHash NOTIFY torrentChanged)
    Q_PROPERTY(int      torrentSeeders     READ torrentSeeders     NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentListSeeders READ torrentListSeeders NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentPeers       READ torrentPeers       NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentListPeers   READ torrentListPeers   NOTIFY torrentStatsChanged)
    Q_PROPERTY(double   torrentRatio  READ torrentRatio   NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentUploaded READ torrentUploaded NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentDownloaded READ torrentDownloaded NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentUploadSpeed   READ torrentUploadSpeed   NOTIFY torrentStatsChanged)
    Q_PROPERTY(float    torrentAvailability  READ torrentAvailability  NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentPiecesDone    READ torrentPiecesDone    NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentPiecesTotal   READ torrentPiecesTotal   NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentActiveTimeSecs  READ torrentActiveTimeSecs  NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentSeedingTimeSecs READ torrentSeedingTimeSecs NOTIFY torrentStatsChanged)
    Q_PROPERTY(qint64   torrentWastedBytes   READ torrentWastedBytes   NOTIFY torrentStatsChanged)
    Q_PROPERTY(int      torrentConnections   READ torrentConnections   NOTIFY torrentStatsChanged)
    Q_PROPERTY(bool     torrentHasMetadata  READ torrentHasMetadata  NOTIFY torrentChanged)
    Q_PROPERTY(bool     torrentIsSingleFile READ torrentIsSingleFile NOTIFY torrentChanged)
    Q_PROPERTY(bool     torrentIsPrivate    READ torrentIsPrivate    NOTIFY torrentChanged)
    Q_PROPERTY(QString  torrentResumeData   READ torrentResumeData   NOTIFY torrentChanged)
    Q_PROPERTY(bool torrentDisableDht READ torrentDisableDht WRITE setTorrentDisableDht NOTIFY torrentFlagsChanged)
    Q_PROPERTY(bool torrentDisablePex READ torrentDisablePex WRITE setTorrentDisablePex NOTIFY torrentFlagsChanged)
    Q_PROPERTY(bool torrentDisableLsd READ torrentDisableLsd WRITE setTorrentDisableLsd NOTIFY torrentFlagsChanged)
    // Per-torrent speed and share limits
    Q_PROPERTY(int    perTorrentDownLimitKBps READ perTorrentDownLimitKBps WRITE setPerTorrentDownLimitKBps NOTIFY torrentLimitsChanged)
    Q_PROPERTY(int    perTorrentUpLimitKBps   READ perTorrentUpLimitKBps   WRITE setPerTorrentUpLimitKBps   NOTIFY torrentLimitsChanged)
    Q_PROPERTY(double torrentShareRatioLimit  READ torrentShareRatioLimit  WRITE setTorrentShareRatioLimit  NOTIFY torrentLimitsChanged)
    Q_PROPERTY(int    torrentSeedingTimeLimitMins READ torrentSeedingTimeLimitMins WRITE setTorrentSeedingTimeLimitMins NOTIFY torrentLimitsChanged)
    Q_PROPERTY(int    torrentInactiveSeedingTimeLimitMins READ torrentInactiveSeedingTimeLimitMins WRITE setTorrentInactiveSeedingTimeLimitMins NOTIFY torrentLimitsChanged)
    Q_PROPERTY(int    torrentShareLimitAction READ torrentShareLimitAction WRITE setTorrentShareLimitAction NOTIFY torrentLimitsChanged)
    // yt-dlp integration: marks items that are downloaded via YtdlpTransfer
    // rather than the regular SegmentedTransfer engine.
    Q_PROPERTY(bool     isYtdlp       READ isYtdlp        CONSTANT)
    Q_PROPERTY(QString  ytdlpFormatId READ ytdlpFormatId  NOTIFY ytdlpFormatIdChanged)
    Q_PROPERTY(bool     ytdlpPlaylistMode READ ytdlpPlaylistMode NOTIFY ytdlpPlaylistModeChanged)

public:
    enum class Status { Queued, Checking, Downloading, Moving, Seeding, Paused, Assembling, Completed, Error };
    Q_ENUM(Status)

    explicit DownloadItem(const QString &id, const QUrl &url, QObject *parent = nullptr);
    static void configureDateTimeFormat(int dateStyle, bool use24Hour, bool showSeconds);

    QString      id()            const { return m_id; }
    QString      filename()      const { return m_filename; }
    QUrl         url()           const { return m_url; }
    qint64       totalBytes()    const { return m_totalBytes; }
    qint64       doneBytes()     const { return m_doneBytes; }
    double       progress()      const;
    qint64       speed()         const { return m_speed; }
    QString      status()        const;
    Status       statusEnum()    const { return m_status; }
    QString      category()      const { return m_category; }
    QString      savePath()      const { return m_savePath; }
    QDateTime    addedAt()       const { return m_addedAt; }
    QString      timeLeft()      const;
    bool         resumeCapable() const { return m_resumeCapable; }
    QVariantList segmentData()   const { return m_segmentData; }
    QString      description()   const { return m_description; }
    int          speedLimitKBps() const { return m_speedLimitKBps; }
    QString      errorString()    const { return m_errorString; }
    QString      referrer()       const { return m_referrer; }
    QString      parentUrl()      const { return m_parentUrl; }
    QString      username()       const { return m_username; }
    QString      password()       const { return m_password; }
    QDateTime    lastTryAt()      const { return m_lastTryAt; }
    QString      addedDateStr()   const;
    QString      lastTryDateStr() const;
    void refreshDateStrings() { emit lastTryAtChanged(); }

    void setFilename(const QString &v);
    void setTotalBytes(qint64 v);
    void setDoneBytes(qint64 v);
    void setSpeed(qint64 bytesPerSec);
    void setEtaSpeed(qint64 bytesPerSec);
    void setStatus(Status s);
    void setCategory(const QString &v);
    void setSavePath(const QString &v);
    void setResumeCapable(bool v);
    void setSegmentData(const QVariantList &v);
    void setDescription(const QString &v);
    void setSpeedLimitKBps(int v);
    void setErrorString(const QString &v) { if (m_errorString != v) { m_errorString = v; emit errorStringChanged(); } }
    QString queueId() const { return m_queueId; }
    void setQueueId(const QString &v) { if (m_queueId != v) { m_queueId = v; emit queueIdChanged(); } }
    void setCookies(const QString &v) { m_cookies = v; }
    QString cookies() const { return m_cookies; }
    void setReferrer(const QString &v)  { if (m_referrer  != v) { m_referrer  = v; emit referrerChanged();  } }
    void setParentUrl(const QString &v) { if (m_parentUrl != v) { m_parentUrl = v; emit parentUrlChanged(); } }
    void setUsername(const QString &v)  { if (m_username  != v) { m_username  = v; emit usernameChanged();  } }
    void setPassword(const QString &v)  { if (m_password  != v) { m_password  = v; emit passwordChanged();  } }
    void setLastTryAt(const QDateTime &v) { if (m_lastTryAt != v) { m_lastTryAt = v; emit lastTryAtChanged(); } }
    void setAddedAt(const QDateTime &v) { m_addedAt = v; }
    
    void setFilenameManuallySet(bool v) { m_filenameManuallySet = v; }
    bool isFilenameManuallySet() const { return m_filenameManuallySet; }

    bool isTorrent() const { return m_isTorrent; }
    QString torrentSource() const { return m_torrentSource; }
    QStringList torrentTrackers() const { return m_torrentTrackers; }
    QString torrentInfoHash() const { return m_torrentInfoHash; }
    int torrentSeeders()     const { return m_torrentSeeders; }
    int torrentListSeeders() const { return m_torrentListSeeders; }
    int torrentPeers()       const { return m_torrentPeers; }
    int torrentListPeers()   const { return m_torrentListPeers; }
    double torrentRatio() const { return m_torrentRatio; }
    qint64 torrentUploaded() const { return m_torrentUploaded; }
    qint64 torrentDownloaded() const { return m_torrentDownloaded; }
    qint64 torrentUploadSpeed()    const { return m_torrentUploadSpeed; }
    float  torrentAvailability()   const { return m_torrentAvailability; }
    int    torrentPiecesDone()     const { return m_torrentPiecesDone; }
    int    torrentPiecesTotal()    const { return m_torrentPiecesTotal; }
    qint64 torrentActiveTimeSecs() const { return m_torrentActiveTimeSecs; }
    qint64 torrentSeedingTimeSecs()const { return m_torrentSeedingTimeSecs; }
    qint64 torrentWastedBytes()    const { return m_torrentWastedBytes; }
    int    torrentConnections()    const { return m_torrentConnections; }
    bool torrentHasMetadata()  const { return m_torrentHasMetadata; }
    bool torrentIsSingleFile() const { return m_torrentIsSingleFile; }
    bool torrentIsPrivate()    const { return m_torrentIsPrivate; }
    bool torrentDisableDht()   const { return m_torrentDisableDht; }
    bool torrentDisablePex()   const { return m_torrentDisablePex; }
    bool torrentDisableLsd()   const { return m_torrentDisableLsd; }
    QString torrentResumeData() const { return m_torrentResumeData; }
    void setIsTorrent(bool v);
    void setTorrentSource(const QString &v);
    void setTorrentTrackers(const QStringList &v) { if (m_torrentTrackers != v) { m_torrentTrackers = v; emit torrentChanged(); } }
    void setTorrentInfoHash(const QString &v);
    void setTorrentSeeders(int v);
    void setTorrentListSeeders(int v) { if (m_torrentListSeeders != v) { m_torrentListSeeders = v; emit torrentStatsChanged(); } }
    void setTorrentPeers(int v);
    void setTorrentListPeers(int v)   { if (m_torrentListPeers   != v) { m_torrentListPeers   = v; emit torrentStatsChanged(); } }
    void setTorrentRatio(double v);
    void setTorrentUploaded(qint64 v);
    void setTorrentDownloaded(qint64 v);
    void setTorrentUploadSpeed(qint64 v);
    void setTorrentAvailability(float v)    { if (m_torrentAvailability   != v) { m_torrentAvailability   = v; emit torrentStatsChanged(); } }
    void setTorrentPiecesDone(int v)        { if (m_torrentPiecesDone     != v) { m_torrentPiecesDone     = v; emit torrentStatsChanged(); } }
    void setTorrentPiecesTotal(int v)       { if (m_torrentPiecesTotal    != v) { m_torrentPiecesTotal    = v; emit torrentStatsChanged(); } }
    void setTorrentActiveTimeSecs(qint64 v) { if (m_torrentActiveTimeSecs != v) { m_torrentActiveTimeSecs = v; emit torrentStatsChanged(); } }
    void setTorrentSeedingTimeSecs(qint64 v){ if (m_torrentSeedingTimeSecs!= v) { m_torrentSeedingTimeSecs= v; emit torrentStatsChanged(); } }
    void setTorrentWastedBytes(qint64 v)    { if (m_torrentWastedBytes    != v) { m_torrentWastedBytes    = v; emit torrentStatsChanged(); } }
    void setTorrentConnections(int v)       { if (m_torrentConnections    != v) { m_torrentConnections    = v; emit torrentStatsChanged(); } }
    void setTorrentHasMetadata(bool v);
    void setTorrentIsSingleFile(bool v) { if (m_torrentIsSingleFile != v) { m_torrentIsSingleFile = v; emit torrentChanged(); } }
    void setTorrentIsPrivate(bool v)    { if (m_torrentIsPrivate    != v) { m_torrentIsPrivate    = v; emit torrentChanged(); } }
    void setTorrentDisableDht(bool v)   { if (m_torrentDisableDht   != v) { m_torrentDisableDht   = v; emit torrentFlagsChanged(); } }
    void setTorrentDisablePex(bool v)   { if (m_torrentDisablePex   != v) { m_torrentDisablePex   = v; emit torrentFlagsChanged(); } }
    void setTorrentDisableLsd(bool v)   { if (m_torrentDisableLsd   != v) { m_torrentDisableLsd   = v; emit torrentFlagsChanged(); } }
    void setTorrentResumeData(const QString &v);
    void clearTorrentStats();

    // Per-torrent limits
    int    perTorrentDownLimitKBps() const { return m_perTorrentDownLimitKBps; }
    int    perTorrentUpLimitKBps()   const { return m_perTorrentUpLimitKBps; }
    double torrentShareRatioLimit()  const { return m_torrentShareRatioLimit; }
    int    torrentSeedingTimeLimitMins() const { return m_torrentSeedingTimeLimitMins; }
    int    torrentInactiveSeedingTimeLimitMins() const { return m_torrentInactiveSeedingTimeLimitMins; }
    int    torrentShareLimitAction() const { return m_torrentShareLimitAction; }
    void setPerTorrentDownLimitKBps(int v)   { if (m_perTorrentDownLimitKBps != v) { m_perTorrentDownLimitKBps = v; emit torrentLimitsChanged(); } }
    void setPerTorrentUpLimitKBps(int v)     { if (m_perTorrentUpLimitKBps   != v) { m_perTorrentUpLimitKBps   = v; emit torrentLimitsChanged(); } }
    void setTorrentShareRatioLimit(double v) { if (m_torrentShareRatioLimit  != v) { m_torrentShareRatioLimit  = v; emit torrentLimitsChanged(); } }
    void setTorrentSeedingTimeLimitMins(int v) { if (m_torrentSeedingTimeLimitMins != v) { m_torrentSeedingTimeLimitMins = v; emit torrentLimitsChanged(); } }
    void setTorrentInactiveSeedingTimeLimitMins(int v) { if (m_torrentInactiveSeedingTimeLimitMins != v) { m_torrentInactiveSeedingTimeLimitMins = v; emit torrentLimitsChanged(); } }
    void setTorrentShareLimitAction(int v)   { if (m_torrentShareLimitAction != v) { m_torrentShareLimitAction = v; emit torrentLimitsChanged(); } }

    // yt-dlp fields
    bool    isYtdlp()           const { return m_isYtdlp; }
    QString ytdlpFormatId()     const { return m_ytdlpFormatId; }
    bool    ytdlpPlaylistMode() const { return m_ytdlpPlaylistMode; }
    // JSON blob storing extra yt-dlp options (subtitles, SponsorBlock, etc.) for resume.
    QString ytdlpExtraOptions() const { return m_ytdlpExtraOptions; }
    void setIsYtdlp(bool v)                { m_isYtdlp = v; }
    void setYtdlpFormatId(const QString &v) {
        if (m_ytdlpFormatId != v) { m_ytdlpFormatId = v; emit ytdlpFormatIdChanged(); }
    }
    void setYtdlpPlaylistMode(bool v) {
        if (m_ytdlpPlaylistMode != v) { m_ytdlpPlaylistMode = v; emit ytdlpPlaylistModeChanged(); }
    }
    void setYtdlpExtraOptions(const QString &v) { m_ytdlpExtraOptions = v; }

signals:
    void filenameChanged();
    void totalBytesChanged();
    void doneBytesChanged();
    void speedChanged();
    void timeLeftChanged();
    void statusChanged();
    void categoryChanged();
    void savePathChanged();
    void resumeCapableChanged();
    void segmentDataChanged();
    void descriptionChanged();
    void speedLimitKBpsChanged(int newLimit);
    void errorStringChanged();
    void queueIdChanged();
    void referrerChanged();
    void parentUrlChanged();
    void usernameChanged();
    void passwordChanged();
    void lastTryAtChanged();
    void torrentChanged();
    void torrentStatsChanged();
    void torrentLimitsChanged();
    void torrentFlagsChanged();
    void ytdlpFormatIdChanged();
    void ytdlpPlaylistModeChanged();

private:
    static QString formatDateTime(const QDateTime &dt);
    QString      m_id;
    QUrl         m_url;
    QString      m_filename;
    qint64       m_totalBytes{0};
    qint64       m_doneBytes{0};
    qint64       m_speed{0};
    qint64       m_etaSpeed{0};   // longer-window average used only for ETA calculation
    Status       m_status{Status::Queued};
    QString      m_category{"Other"};
    QString      m_savePath;
    QDateTime    m_addedAt;
    bool         m_resumeCapable{false};
    bool         m_filenameManuallySet{false};
    QVariantList m_segmentData;
    QString      m_description;
    int          m_speedLimitKBps{0};
    QString      m_errorString;
    QString      m_queueId;
    QString      m_cookies;
    QString      m_referrer;
    QString      m_parentUrl;
    QString      m_username;
    QString      m_password;
    QDateTime    m_lastTryAt;
    bool         m_isTorrent{false};
    QString      m_torrentSource;
    QStringList  m_torrentTrackers;
    QString      m_torrentInfoHash;
    int          m_torrentSeeders{0};
    int          m_torrentListSeeders{0};
    int          m_torrentPeers{0};
    int          m_torrentListPeers{0};
    double       m_torrentRatio{0.0};
    qint64       m_torrentUploaded{0};
    qint64       m_torrentDownloaded{0};
    qint64       m_torrentUploadSpeed{0};
    float        m_torrentAvailability{0.f};
    int          m_torrentPiecesDone{0};
    int          m_torrentPiecesTotal{0};
    qint64       m_torrentActiveTimeSecs{0};
    qint64       m_torrentSeedingTimeSecs{0};
    qint64       m_torrentWastedBytes{0};
    int          m_torrentConnections{0};
    bool         m_torrentHasMetadata{false};
    bool         m_torrentIsSingleFile{true};   // true until metadata proves otherwise
    bool         m_torrentIsPrivate{false};
    bool         m_torrentDisableDht{false};
    bool         m_torrentDisablePex{false};
    bool         m_torrentDisableLsd{false};
    QString      m_torrentResumeData;
    int          m_perTorrentDownLimitKBps{0};
    int          m_perTorrentUpLimitKBps{0};
    double       m_torrentShareRatioLimit{-1.0};
    int          m_torrentSeedingTimeLimitMins{-1};
    int          m_torrentInactiveSeedingTimeLimitMins{-1};
    int          m_torrentShareLimitAction{-1};
    bool         m_isYtdlp{false};      // true → YtdlpTransfer manages this item
    QString      m_ytdlpFormatId;       // yt-dlp format selector used for this download
    bool         m_ytdlpPlaylistMode{false};
    QString      m_ytdlpExtraOptions;   // JSON blob of extra yt-dlp options for resume
    static int   s_dateStyle;
    static bool  s_use24Hour;
    static bool  s_showSeconds;
};
