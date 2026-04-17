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

#include "DownloadDatabase.h"
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSaveFile>
#include <QDebug>

namespace {

// Simple obfuscation (NOT encryption) for stored HTTP credentials.
// Goal: prevent casual exposure via cloud backups, log grepping, or shoulder
// surfing.  A motivated attacker with access to the binary can trivially
// reverse this — that is an accepted limitation for this threat model.
//
// Stored format: "~e~" prefix + Base64( plaintext XOR key ).
// The prefix lets us detect legacy plaintext values saved by older versions
// and return them as-is (backwards compatible read path).
static const char kCredKey[] = "S7t3ll@rDM!k3y#9";
static const QLatin1String kCredPrefix("~e~");

QString obfuscateCred(const QString &plain)
{
    if (plain.isEmpty()) return {};
    QByteArray data = plain.toUtf8();
    const int keyLen = static_cast<int>(sizeof(kCredKey) - 1);
    for (int i = 0; i < data.size(); ++i)
        data[i] = static_cast<char>(static_cast<unsigned char>(data[i]) ^ static_cast<unsigned char>(kCredKey[i % keyLen]));
    return kCredPrefix + QString::fromLatin1(data.toBase64());
}

QString deobfuscateCred(const QString &stored)
{
    if (stored.isEmpty()) return {};
    // Legacy plaintext (written by older versions before obfuscation was added)
    if (!stored.startsWith(kCredPrefix))
        return stored;
    QByteArray data = QByteArray::fromBase64(stored.mid(kCredPrefix.size()).toLatin1());
    const int keyLen = static_cast<int>(sizeof(kCredKey) - 1);
    for (int i = 0; i < data.size(); ++i)
        data[i] = static_cast<char>(static_cast<unsigned char>(data[i]) ^ static_cast<unsigned char>(kCredKey[i % keyLen]));
    return QString::fromUtf8(data);
}

} // namespace

DownloadDatabase::DownloadDatabase(QObject *parent) : QObject(parent) {
    m_writeTimer.setSingleShot(true);
    m_writeTimer.setInterval(150);   // coalesce rapid save/remove calls
    connect(&m_writeTimer, &QTimer::timeout, this, &DownloadDatabase::commitToDisk);
}

bool DownloadDatabase::open() {
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    m_filePath = dataDir + QStringLiteral("/downloads.json");
    return true;
}

QList<DownloadItem *> DownloadDatabase::loadAll() {
    QList<DownloadItem *> result;
    m_entries.clear();

    QFile f(m_filePath);
    if (!f.exists()) return result;
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << "DownloadDatabase: cannot read" << m_filePath;
        return result;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isArray()) return result;

    const QJsonArray arr = doc.array();
    for (const QJsonValue &val : arr) {
        const QJsonObject obj = val.toObject();
        const QString id  = obj[QLatin1String("id")].toString();
        const QUrl    url = QUrl(obj[QLatin1String("url")].toString());
        if (id.isEmpty() || url.isEmpty()) continue;

        auto *item = new DownloadItem(id, url);
        item->setFilename(obj[QLatin1String("filename")].toString());
        item->setSavePath(obj[QLatin1String("savePath")].toString());
        item->setCategory(obj[QLatin1String("category")].toString());
        item->setDescription(obj[QLatin1String("description")].toString());
        item->setTotalBytes(obj[QLatin1String("totalBytes")].toVariant().toLongLong());
        item->setDoneBytes(obj[QLatin1String("doneBytes")].toVariant().toLongLong());
        item->setResumeCapable(obj[QLatin1String("resumeCapable")].toBool());
        item->setReferrer(obj[QLatin1String("referrer")].toString());
        item->setParentUrl(obj[QLatin1String("parentUrl")].toString());
        item->setUsername(deobfuscateCred(obj[QLatin1String("username")].toString()));
        item->setPassword(deobfuscateCred(obj[QLatin1String("password")].toString()));
        {
            const QString ltStr = obj[QLatin1String("lastTryAt")].toString();
            if (!ltStr.isEmpty()) item->setLastTryAt(QDateTime::fromString(ltStr, Qt::ISODate));
        }
        {
            const QString queueId = obj[QLatin1String("queueId")].toString();
            if (!queueId.isEmpty()) item->setQueueId(queueId);
        }
        {
            const QString addedStr = obj[QLatin1String("addedAt")].toString();
            if (!addedStr.isEmpty()) item->setAddedAt(QDateTime::fromString(addedStr, Qt::ISODate));
        }

        // Restore yt-dlp fields; absent key → false/empty for regular downloads
        item->setIsYtdlp(obj[QLatin1String("isYtdlp")].toBool(false));
        item->setYtdlpFormatId(obj[QLatin1String("ytdlpFormatId")].toString());
        item->setYtdlpPlaylistMode(obj[QLatin1String("ytdlpPlaylistMode")].toBool(false));
        item->setYtdlpExtraOptions(obj[QLatin1String("ytdlpExtraOptions")].toString());
        item->setIsTorrent(obj[QLatin1String("isTorrent")].toBool(false));
        item->setTorrentSource(obj[QLatin1String("torrentSource")].toString());
        item->setTorrentTrackers(obj[QLatin1String("torrentTrackers")].toVariant().toStringList());
        item->setTorrentInfoHash(obj[QLatin1String("torrentInfoHash")].toString());
        item->setTorrentSeeders(obj[QLatin1String("torrentSeeders")].toInt());
        item->setTorrentPeers(obj[QLatin1String("torrentPeers")].toInt());
        item->setTorrentRatio(obj[QLatin1String("torrentRatio")].toDouble(0.0));
        item->setTorrentUploaded(obj[QLatin1String("torrentUploaded")].toVariant().toLongLong());
        item->setTorrentDownloaded(obj[QLatin1String("torrentDownloaded")].toVariant().toLongLong());
        item->setTorrentUploadSpeed(obj[QLatin1String("torrentUploadSpeed")].toVariant().toLongLong());
        item->setTorrentHasMetadata(obj[QLatin1String("torrentHasMetadata")].toBool(false));
        item->setTorrentIsSingleFile(obj[QLatin1String("torrentIsSingleFile")].toBool(true));
        item->setTorrentDisableDht(obj[QLatin1String("torrentDisableDht")].toBool(false));
        item->setTorrentDisablePex(obj[QLatin1String("torrentDisablePex")].toBool(false));
        item->setTorrentDisableLsd(obj[QLatin1String("torrentDisableLsd")].toBool(false));
        item->setTorrentResumeData(obj[QLatin1String("torrentResumeData")].toString());
        item->setPerTorrentDownLimitKBps(obj[QLatin1String("perTorrentDownLimitKBps")].toInt(0));
        item->setPerTorrentUpLimitKBps(obj[QLatin1String("perTorrentUpLimitKBps")].toInt(0));
        item->setTorrentShareRatioLimit(obj[QLatin1String("torrentShareRatioLimit")].toDouble(-1.0));
        item->setTorrentSeedingTimeLimitMins(obj[QLatin1String("torrentSeedingTimeLimitMins")].toInt(-1));
        item->setTorrentInactiveSeedingTimeLimitMins(obj[QLatin1String("torrentInactiveSeedingTimeLimitMins")].toInt(-1));
        item->setTorrentShareLimitAction(obj[QLatin1String("torrentShareLimitAction")].toInt(-1));

        const QString statusStr = obj[QLatin1String("status")].toString();
        DownloadItem::Status s = DownloadItem::Status::Paused;
        if (statusStr == QLatin1String("Checking"))         s = DownloadItem::Status::Checking;
        else if (statusStr == QLatin1String("Downloading")) s = DownloadItem::Status::Downloading;
        else if (statusStr == QLatin1String("Seeding"))     s = DownloadItem::Status::Seeding;
        else if (statusStr == QLatin1String("Paused"))      s = DownloadItem::Status::Paused;
        else if (statusStr == QLatin1String("Completed"))   s = DownloadItem::Status::Completed;
        else if (statusStr == QLatin1String("Error"))       s = DownloadItem::Status::Error;
        else if (statusStr == QLatin1String("Queued")) {
            s = item->isTorrent() ? DownloadItem::Status::Downloading : DownloadItem::Status::Paused;
        }
        else if (statusStr == QLatin1String("Assembling...")) s = DownloadItem::Status::Paused;
        item->setStatus(s);

        m_entries[id] = obj.toVariantMap();
        result.append(item);
    }
    return result;
}

void DownloadDatabase::save(DownloadItem *item) {
    if (!item) return;

    QVariantMap m;
    m[QStringLiteral("id")]             = item->id();
    m[QStringLiteral("url")]            = item->url().toString();
    m[QStringLiteral("filename")]       = item->filename();
    m[QStringLiteral("savePath")]       = item->savePath();
    m[QStringLiteral("category")]       = item->category();
    m[QStringLiteral("description")]    = item->description();
    m[QStringLiteral("totalBytes")]     = item->totalBytes();
    m[QStringLiteral("doneBytes")]      = item->doneBytes();
    m[QStringLiteral("status")]         = item->status();
    m[QStringLiteral("resumeCapable")]  = item->resumeCapable();
    m[QStringLiteral("addedAt")]        = item->addedAt().toString(Qt::ISODate);
    m[QStringLiteral("referrer")]       = item->referrer();
    m[QStringLiteral("parentUrl")]      = item->parentUrl();
    // Only persist credentials when present; obfuscate to avoid plaintext in backups.
    if (!item->username().isEmpty())
        m[QStringLiteral("username")] = obfuscateCred(item->username());
    if (!item->password().isEmpty())
        m[QStringLiteral("password")] = obfuscateCred(item->password());
    m[QStringLiteral("queueId")]        = item->queueId();
    if (item->lastTryAt().isValid())
        m[QStringLiteral("lastTryAt")] = item->lastTryAt().toString(Qt::ISODate);
    // yt-dlp items need their engine flag and format selector preserved across restarts
    if (item->isYtdlp()) {
        m[QStringLiteral("isYtdlp")]           = true;
        m[QStringLiteral("ytdlpFormatId")]     = item->ytdlpFormatId();
        m[QStringLiteral("ytdlpPlaylistMode")] = item->ytdlpPlaylistMode();
        if (!item->ytdlpExtraOptions().isEmpty())
            m[QStringLiteral("ytdlpExtraOptions")] = item->ytdlpExtraOptions();
    }
    if (item->isTorrent()) {
        m[QStringLiteral("isTorrent")] = true;
        m[QStringLiteral("torrentSource")] = item->torrentSource();
        m[QStringLiteral("torrentTrackers")] = item->torrentTrackers();
        m[QStringLiteral("torrentInfoHash")] = item->torrentInfoHash();
        m[QStringLiteral("torrentSeeders")] = item->torrentSeeders();
        m[QStringLiteral("torrentPeers")] = item->torrentPeers();
        m[QStringLiteral("torrentRatio")] = item->torrentRatio();
        m[QStringLiteral("torrentUploaded")] = item->torrentUploaded();
        m[QStringLiteral("torrentDownloaded")] = item->torrentDownloaded();
        m[QStringLiteral("torrentUploadSpeed")] = item->torrentUploadSpeed();
        m[QStringLiteral("torrentHasMetadata")]  = item->torrentHasMetadata();
        m[QStringLiteral("torrentIsSingleFile")] = item->torrentIsSingleFile();
        m[QStringLiteral("torrentDisableDht")]   = item->torrentDisableDht();
        m[QStringLiteral("torrentDisablePex")]   = item->torrentDisablePex();
        m[QStringLiteral("torrentDisableLsd")]   = item->torrentDisableLsd();
        m[QStringLiteral("torrentResumeData")] = item->torrentResumeData();
        m[QStringLiteral("perTorrentDownLimitKBps")] = item->perTorrentDownLimitKBps();
        m[QStringLiteral("perTorrentUpLimitKBps")]   = item->perTorrentUpLimitKBps();
        m[QStringLiteral("torrentShareRatioLimit")]  = item->torrentShareRatioLimit();
        m[QStringLiteral("torrentSeedingTimeLimitMins")] = item->torrentSeedingTimeLimitMins();
        m[QStringLiteral("torrentInactiveSeedingTimeLimitMins")] = item->torrentInactiveSeedingTimeLimitMins();
        m[QStringLiteral("torrentShareLimitAction")] = item->torrentShareLimitAction();
    }

    m_entries[item->id()] = m;
    scheduleDiskWrite();
}

void DownloadDatabase::remove(const QString &id) {
    if (m_entries.remove(id))
        scheduleDiskWrite();
}

void DownloadDatabase::flush() {
    m_writeTimer.stop();
    commitToDisk();
}

void DownloadDatabase::scheduleDiskWrite() {
    // (Re-)start the timer. If called again within the interval the previous
    // pending write is cancelled and a fresh one is scheduled — so a burst of
    // 200 remove() calls results in exactly one file write.
    m_writeTimer.start();
}

void DownloadDatabase::commitToDisk() {
    QJsonArray arr;
    for (auto it = m_entries.constBegin(); it != m_entries.constEnd(); ++it)
        arr.append(QJsonObject::fromVariantMap(it.value()));

    QSaveFile f(m_filePath);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "DownloadDatabase: cannot write" << m_filePath;
        return;
    }
    if (f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact)) < 0 || !f.commit())
        qWarning() << "DownloadDatabase: cannot commit" << m_filePath;
}
