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

#include "DataPortability.h"
#include "StellarPaths.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace DataPortability {
namespace {

constexpr auto kVersionKey  = "stellar_export_version";
constexpr auto kAppVerKey   = "app_version";
constexpr auto kCreatedKey  = "created";
constexpr auto kFilesKey    = "files";

// Read a file and add it to the container object under the given relative key.
// Missing files are silently skipped — a fresh install legitimately lacks some.
void addFileToObject(QJsonObject &files, const QString &absPath, const QString &key)
{
    QFile f(absPath);
    if (!f.exists())
        return;
    if (!f.open(QIODevice::ReadOnly))
        return;
    files.insert(key, QString::fromLatin1(f.readAll().toBase64()));
}

// Add every file matching a name filter in a directory, keyed "<prefix>/<name>".
void addDirToObject(QJsonObject &files, const QString &dirPath,
                    const QStringList &nameFilters, const QString &keyPrefix)
{
    const QFileInfoList entries =
        QDir(dirPath).entryInfoList(nameFilters, QDir::Files);
    for (const QFileInfo &fi : entries)
        addFileToObject(files, fi.absoluteFilePath(),
                        keyPrefix + QLatin1Char('/') + fi.fileName());
}

// Recursively copy a directory tree into destDir (created if needed).
bool copyTree(const QString &srcDir, const QString &destDir)
{
    QDir src(srcDir);
    if (!src.exists())
        return true;                       // nothing to copy is not an error
    if (!QDir().mkpath(destDir))
        return false;

    const QFileInfoList entries = src.entryInfoList(
        QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const QFileInfo &fi : entries) {
        const QString dest = destDir + QLatin1Char('/') + fi.fileName();
        if (fi.isDir()) {
            if (!copyTree(fi.absoluteFilePath(), dest))
                return false;
        } else {
            QFile::remove(dest);           // QFile::copy fails if dest exists
            if (!QFile::copy(fi.absoluteFilePath(), dest))
                return false;
        }
    }
    return true;
}

// Write base64-decoded bytes to "<root>/<key>", creating parent dirs.
bool writeKeyToDisk(const QString &root, const QString &key, const QByteArray &b64)
{
    const QString destPath = root + QLatin1Char('/') + key;
    if (!QDir().mkpath(QFileInfo(destPath).absolutePath()))
        return false;

    QSaveFile out(destPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    out.write(QByteArray::fromBase64(b64));
    return out.commit();
}

} // namespace

Result exportTo(const QString &destPath)
{
    QJsonObject files;

    // ── Fixed single files (all under StellarPaths) ──────────────────────────
    addFileToObject(files, StellarPaths::settingsFile(),        QStringLiteral("settings.ini"));
    addFileToObject(files, StellarPaths::downloadsFile(),       QStringLiteral("data/downloads.json"));
    addFileToObject(files, StellarPaths::queuesFile(),          QStringLiteral("data/queues.json"));
    addFileToObject(files, StellarPaths::categoriesFile(),      QStringLiteral("data/categories.json"));
    addFileToObject(files, StellarPaths::grabberProjectsFile(), QStringLiteral("data/grabber_projects.json"));
    addFileToObject(files, StellarPaths::rssFeedsFile(),        QStringLiteral("data/rss_feeds.json"));
    addFileToObject(files, StellarPaths::rssRulesFile(),        QStringLiteral("data/rss_rules.json"));
    addFileToObject(files, StellarPaths::dataDir() + QStringLiteral("/rss_autodownloaded.json"),
                    QStringLiteral("data/rss_autodownloaded.json"));
    addFileToObject(files, StellarPaths::statisticsFile(),      QStringLiteral("data/statistics.json"));

    // ── Per-torrent fast-resume blobs and user search plugins ────────────────
    addDirToObject(files, StellarPaths::resumeDir(),        {QStringLiteral("*.resume")}, QStringLiteral("resume"));
    addDirToObject(files, StellarPaths::searchPluginsDir(), {QStringLiteral("*.py")},     QStringLiteral("plugins/search"));

    QJsonObject root;
    root.insert(QLatin1String(kVersionKey), kExportVersion);
    root.insert(QLatin1String(kAppVerKey),  QCoreApplication::applicationVersion());
    root.insert(QLatin1String(kCreatedKey),
                QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    root.insert(QLatin1String(kFilesKey),   files);

    QSaveFile out(destPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return { false, QStringLiteral("Could not open the destination file for writing.") };
    out.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    if (!out.commit())
        return { false, QStringLiteral("Failed to write the backup file.") };

    return { true, {} };
}

Result importFrom(const QString &srcPath, bool backupExisting)
{
    QFile in(srcPath);
    if (!in.open(QIODevice::ReadOnly))
        return { false, QStringLiteral("Could not open the backup file.") };

    QJsonParseError perr{};
    const QJsonDocument doc = QJsonDocument::fromJson(in.readAll(), &perr);
    in.close();
    if (perr.error != QJsonParseError::NoError || !doc.isObject())
        return { false, QStringLiteral("The file is not a valid Stellar backup.") };

    const QJsonObject root = doc.object();

    // Validate the schema version BEFORE touching any on-disk data.
    if (!root.contains(QLatin1String(kVersionKey)))
        return { false, QStringLiteral("The file is not a valid Stellar backup.") };
    const int version = root.value(QLatin1String(kVersionKey)).toInt(-1);
    if (version < 1 || version > kExportVersion)
        return { false, QStringLiteral("This backup was created by a newer version of Stellar "
                                       "and cannot be imported.") };

    const QJsonObject files = root.value(QLatin1String(kFilesKey)).toObject();
    if (files.isEmpty())
        return { false, QStringLiteral("The backup contains no data to restore.") };

    const QString stellarRoot = StellarPaths::root();

    // Back up the current data tree so a mistaken import is recoverable.
    if (backupExisting) {
        const QString stamp =
            QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
        const QString backupDir =
            stellarRoot + QStringLiteral(".backup-") + stamp;
        if (!copyTree(stellarRoot, backupDir))
            return { false, QStringLiteral("Could not back up the existing data; import aborted.") };
    }

    // Write every embedded file back under the Stellar root.
    for (auto it = files.constBegin(); it != files.constEnd(); ++it) {
        const QString key = it.key();
        if (key.contains(QStringLiteral("..")))     // guard against path escape
            continue;
        if (!writeKeyToDisk(stellarRoot, key, it.value().toString().toLatin1()))
            return { false, QStringLiteral("Failed while restoring \"%1\".").arg(key) };
    }

    return { true, {} };
}

} // namespace DataPortability
