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

#include "StellarPaths.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>
#include <QDebug>

namespace StellarPaths {

// ── Root ─────────────────────────────────────────────────────────────────────

QString root()
{
    // Prefer AppLocalDataLocation (%LOCALAPPDATA% on Windows,
    // $XDG_DATA_HOME on Linux) because it is user-private and always writable.
    // Fall back to the roaming AppDataLocation only when the local location is
    // unavailable (very unusual, but possible in constrained environments).
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty())
        base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (base.isEmpty())
        base = QCoreApplication::applicationDirPath();

    // Qt appends "<OrgName>/<AppName>" to the standard location, producing the
    // ugly StellarDownloadManager/StellarDownloadManager nesting.  We strip
    // both components and replace them with a single clean "Stellar" directory.
    //
    // e.g. C:/Users/Alice/AppData/Local/StellarDownloadManager/StellarDownloadManager
    //   →  C:/Users/Alice/AppData/Local/Stellar
    //
    // We match by checking whether the path ends with the Qt-appended suffix
    // rather than hard-coding its absolute value, so the stripping is robust
    // across Qt version differences and future renames.
    const QString orgApp  = QCoreApplication::organizationName()
                            + QLatin1Char('/')
                            + QCoreApplication::applicationName();
    const QString orgOnly = QCoreApplication::organizationName();

    // QStandardPaths uses forward slashes internally.
    if (base.endsWith(orgApp, Qt::CaseInsensitive))
        base.chop(orgApp.size() + 1);          // strip trailing slash too
    else if (base.endsWith(orgOnly, Qt::CaseInsensitive))
        base.chop(orgOnly.size() + 1);

    const QString dir = base + QStringLiteral("/Stellar");
    QDir().mkpath(dir);
    return dir;
}

// ── Sub-directories ───────────────────────────────────────────────────────────

QString dataDir()
{
    const QString dir = root() + QStringLiteral("/data");
    QDir().mkpath(dir);
    return dir;
}

QString resumeDir()
{
    const QString dir = root() + QStringLiteral("/resume");
    QDir().mkpath(dir);
    return dir;
}

QString pluginsDir()
{
    const QString dir = root() + QStringLiteral("/plugins");
    QDir().mkpath(dir);
    return dir;
}

QString searchPluginsDir()
{
    const QString dir = pluginsDir() + QStringLiteral("/search");
    QDir().mkpath(dir);
    return dir;
}

QString binDir()
{
    const QString dir = root() + QStringLiteral("/bin");
    QDir().mkpath(dir);
    return dir;
}

QString geoDir()
{
    const QString dir = root() + QStringLiteral("/geo");
    QDir().mkpath(dir);
    return dir;
}

QString cacheDir()
{
    const QString dir = root() + QStringLiteral("/cache");
    QDir().mkpath(dir);
    return dir;
}

// ── Individual files ──────────────────────────────────────────────────────────

QString settingsFile()
{
    return root() + QStringLiteral("/settings.ini");
}

QString downloadsFile()
{
    return dataDir() + QStringLiteral("/downloads.json");
}

QString queuesFile()
{
    return dataDir() + QStringLiteral("/queues.json");
}

QString grabberProjectsFile()
{
    return dataDir() + QStringLiteral("/grabber_projects.json");
}

QString rssFeedsFile()
{
    return dataDir() + QStringLiteral("/rss_feeds.json");
}

QString rssRulesFile()
{
    return dataDir() + QStringLiteral("/rss_rules.json");
}

QString searchRunnerFile()
{
    return pluginsDir() + QStringLiteral("/torrent_search_runner.py");
}

QString resumeFile(const QString &downloadId)
{
    // Filenames are download IDs, which are UUIDs — always safe as filenames.
    return resumeDir() + QLatin1Char('/') + downloadId + QStringLiteral(".resume");
}

// ── Migration ─────────────────────────────────────────────────────────────────

namespace {

// Move a single file from |src| to |dst|, creating parent directories as
// needed.  Overwrites dst only if src exists and dst does not yet exist
// (we never clobber data the new layout already has).
void migrateFile(const QString &src, const QString &dst)
{
    if (!QFile::exists(src) || QFile::exists(dst))
        return;
    QDir().mkpath(QFileInfo(dst).absolutePath());
    if (!QFile::rename(src, dst))
        qWarning() << "[StellarPaths] migrate: could not move" << src << "→" << dst;
    else
        qDebug()   << "[StellarPaths] migrate:" << src << "→" << dst;
}

// Move every *.py file in |srcDir| to |dstDir|.
void migratePlugins(const QString &srcDir, const QString &dstDir)
{
    const QFileInfoList files =
        QDir(srcDir).entryInfoList({ QStringLiteral("*.py") }, QDir::Files);
    for (const QFileInfo &fi : files)
        migrateFile(fi.absoluteFilePath(), dstDir + QLatin1Char('/') + fi.fileName());
}

// Move every file in |srcDir| whose name matches |nameFilter| to |dstDir|.
void migrateGlob(const QString &srcDir, const QString &nameFilter, const QString &dstDir)
{
    const QFileInfoList files =
        QDir(srcDir).entryInfoList({ nameFilter }, QDir::Files);
    for (const QFileInfo &fi : files)
        migrateFile(fi.absoluteFilePath(), dstDir + QLatin1Char('/') + fi.fileName());
}

// Recursively remove |dir| if it is empty (or contains only empty sub-dirs).
// We walk bottom-up so a directory is only removed after its children are gone.
void removeIfEmpty(const QString &path)
{
    QDir d(path);
    for (const QFileInfo &fi : d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
        removeIfEmpty(fi.absoluteFilePath());
    // Re-check: might now be empty after the recursive calls.
    if (d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty())
        d.rmdir(path);
}

} // anonymous namespace

void migrateIfNeeded()
{
    // ── Locate the legacy root ────────────────────────────────────────────────
    // The old code used QStandardPaths with org="StellarDownloadManager" and
    // app="StellarDownloadManager", which produced:
    //   Windows : %APPDATA%\StellarDownloadManager\StellarDownloadManager\
    //   Linux   : $XDG_DATA_HOME/StellarDownloadManager/StellarDownloadManager/  (AppDataLocation)
    // and for the tools dir it used AppLocalDataLocation:
    //   Windows : %LOCALAPPDATA%\StellarDownloadManager\StellarDownloadManager\tools\
    //
    // We find the legacy root by asking Qt for AppDataLocation with the old
    // org/app names — Qt resolves this portably on every platform.
    const QString legacyBase =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    // legacyBase already contains …/StellarDownloadManager/StellarDownloadManager
    // because the application org/name have not changed yet at this call site
    // (migration runs early in main(), before we change them).

    // Legacy local-data root (only differs from legacyBase on Windows where
    // Local ≠ Roaming AppData).
    const QString legacyLocalBase =
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);

    if (!QDir(legacyBase).exists() && !QDir(legacyLocalBase).exists())
        return;   // nothing to migrate

    // Guard: skip if the migration was already completed in a previous run.
    // We store the flag in the *new* settings file so the old data dir being
    // present (e.g. because the user put something else there) doesn't re-trigger.
    QSettings newSettings(settingsFile(), QSettings::IniFormat);
    if (newSettings.value(QStringLiteral("migrationDone")).toBool())
        return;

    qDebug() << "[StellarPaths] Running one-time data migration from legacy layout…";

    // ── JSON databases ────────────────────────────────────────────────────────
    migrateFile(legacyBase + QStringLiteral("/downloads.json"),        downloadsFile());
    migrateFile(legacyBase + QStringLiteral("/queues.json"),           queuesFile());
    migrateFile(legacyBase + QStringLiteral("/categories.json"),
                dataDir()  + QStringLiteral("/categories.json"));
    migrateFile(legacyBase + QStringLiteral("/grabber_projects.json"), grabberProjectsFile());
    migrateFile(legacyBase + QStringLiteral("/rss_feeds.json"), rssFeedsFile());

    // ── Torrent search runner + plugins ───────────────────────────────────────
    migrateFile(legacyBase + QStringLiteral("/torrent_search_runner.py"), searchRunnerFile());
    migratePlugins(legacyBase + QStringLiteral("/search_plugins"), searchPluginsDir());

    // ── Binaries ──────────────────────────────────────────────────────────────
    // Old "tools" directory lived under AppLocalDataLocation on Windows.
    const QString legacyToolsDir = legacyLocalBase + QStringLiteral("/tools");
#if defined(Q_OS_WIN)
    migrateFile(legacyToolsDir + QStringLiteral("/yt-dlp.exe"),   binDir() + QStringLiteral("/yt-dlp.exe"));
    migrateFile(legacyToolsDir + QStringLiteral("/ffmpeg.exe"),   binDir() + QStringLiteral("/ffmpeg.exe"));
    migrateFile(legacyToolsDir + QStringLiteral("/ffprobe.exe"),  binDir() + QStringLiteral("/ffprobe.exe"));
    // SHA-512 sums file used for update integrity verification
    migrateFile(legacyToolsDir + QStringLiteral("/SHA2-512SUMS"), binDir() + QStringLiteral("/SHA2-512SUMS"));
#else
    migrateFile(legacyToolsDir + QStringLiteral("/yt-dlp"),    binDir() + QStringLiteral("/yt-dlp"));
    migrateFile(legacyToolsDir + QStringLiteral("/ffmpeg"),    binDir() + QStringLiteral("/ffmpeg"));
    migrateFile(legacyToolsDir + QStringLiteral("/ffprobe"),   binDir() + QStringLiteral("/ffprobe"));
    migrateFile(legacyToolsDir + QStringLiteral("/SHA2-512SUMS"), binDir() + QStringLiteral("/SHA2-512SUMS"));
#endif

    // ── Geo-IP databases ──────────────────────────────────────────────────────
    const QString legacyDataDir = legacyLocalBase + QStringLiteral("/data");
    migrateGlob(legacyDataDir, QStringLiteral("*.mmdb"), geoDir());

    // ── Migrate QSettings from native format to the new INI file ─────────────
    // Read every key from the old registry (Windows) / INI (Linux) store and
    // write it into the new settings.ini — but only when the new file does not
    // already have a value for that key.  This preserves any settings the user
    // may have changed after a partial migration.
    {
        QSettings oldSettings(QStringLiteral("StellarDownloadManager"),
                              QStringLiteral("StellarDownloadManager"));
        const QStringList keys = oldSettings.allKeys();
        for (const QString &key : keys) {
            if (!newSettings.contains(key))
                newSettings.setValue(key, oldSettings.value(key));
        }
        newSettings.sync();
    }

    // ── Clean up empty legacy directories ─────────────────────────────────────
    removeIfEmpty(legacyBase);
    if (legacyLocalBase != legacyBase)
        removeIfEmpty(legacyLocalBase);

    // Mark migration complete so this function is a cheap no-op on all future starts.
    newSettings.setValue(QStringLiteral("migrationDone"), true);
    newSettings.sync();

    qDebug() << "[StellarPaths] Migration complete.";
}

} // namespace StellarPaths
