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
#include <QDebug>

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
        item->setUsername(obj[QLatin1String("username")].toString());
        item->setPassword(obj[QLatin1String("password")].toString());
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

        const QString statusStr = obj[QLatin1String("status")].toString();
        DownloadItem::Status s = DownloadItem::Status::Paused;
        if (statusStr == QLatin1String("Completed"))        s = DownloadItem::Status::Completed;
        else if (statusStr == QLatin1String("Error"))       s = DownloadItem::Status::Error;
        else if (statusStr == QLatin1String("Queued"))      s = DownloadItem::Status::Paused;
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
    m[QStringLiteral("username")]       = item->username();
    m[QStringLiteral("password")]       = item->password();
    m[QStringLiteral("queueId")]        = item->queueId();
    if (item->lastTryAt().isValid())
        m[QStringLiteral("lastTryAt")] = item->lastTryAt().toString(Qt::ISODate);

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

    QFile f(m_filePath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "DownloadDatabase: cannot write" << m_filePath;
        return;
    }
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    f.close();
}
