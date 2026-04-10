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

public:
    enum class Status { Queued, Downloading, Paused, Assembling, Completed, Error };
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

private:
    static QString formatDateTime(const QDateTime &dt);
    QString      m_id;
    QUrl         m_url;
    QString      m_filename;
    qint64       m_totalBytes{0};
    qint64       m_doneBytes{0};
    qint64       m_speed{0};
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
    static int   s_dateStyle;
    static bool  s_use24Hour;
    static bool  s_showSeconds;
};
