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

#include "AppSettings.h"
#include "AppVersion.h"
#include "StellarPaths.h"
#include "DownloadDatabase.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>
#include <QDateTime>

// ============================================================================
// Type-conversion helpers for load() lines
// ============================================================================
#define CONV_int .toInt()
#define CONV_bool .toBool()
#define CONV_double .toDouble()
#define CONV_QString .toString()
#define CONV_QStringList .toStringList()
#define CONVERT(ptype) CONV_##ptype

// ============================================================================
// Setter dispatch — picks the right implementation per flag
// ============================================================================
#define SETTER_N(ptype, sp, mem, camel, def, key) \
    void AppSettings::set##camel(sp v) { if (m_##mem != v) { m_##mem = v; emit mem##Changed(); save(); } }
#define SETTER_T(ptype, sp, mem, camel, def, key) \
    void AppSettings::set##camel(sp v) { if (m_##mem != v) { m_##mem = v; emit torrentSettingsChanged(); save(); } }
#define SETTER_S(ptype, sp, mem, camel, def, key) \
    void AppSettings::set##camel(sp v) { if (m_##mem != v) { m_##mem = v; emit mem##Changed(); scheduleSave(); } }
#define SETTER(ptype, sp, mem, camel, def, key, flags) SETTER_##flags(ptype, sp, mem, camel, def, key)

// ============================================================================
// Load-emit dispatch
// ============================================================================
#define LEMIT_N(ptype, sp, mem, camel, def, key) emit mem##Changed();
#define LEMIT_T(ptype, sp, mem, camel, def, key) /* covered by manual emit torrentSettingsChanged */
#define LEMIT_S(ptype, sp, mem, camel, def, key) emit mem##Changed();
#define LEMIT(ptype, sp, mem, camel, def, key, flags) LEMIT_##flags(ptype, sp, mem, camel, def, key)

QStringList AppSettings::defaultMonitoredExtensions() {
    return {
        "3gp","7z","aac","ace","aif","apk","arj","asf","avi","bin","bz2",
        "exe","gz","gzip","img","iso","lzh","m4a","m4v","mkv","mov","mp3",
        "mp4","mpa","mpe","mpeg","mpg","msi","msu","ogg","ogv","pdf","plj",
        "pps","ppt","qt","r00","r01","ra","rar","rm","rmvb","sea","sit","sitx",
        "tar","tif","tiff","wav","wma","wmv","z","zip",
        "safetensors","gguf","azw3","unitypackage"
    };
}

QStringList AppSettings::defaultExcludedSites() {
    return {
        "*.update.microsoft.com",
        "download.windowsupdate.com",
        "*.download.windowsupdate.com",
        "siteseal.thawte.com",
        "ecom.cimetz.com",
        "*.voice2page.com",
        "download.sophos.com"
    };
}

QStringList AppSettings::defaultExcludedAddresses() {
    return {
        "http://*.appspot.com/*/*mp3",
        "http://*.akamaihd.net/*.mp3",
        "http://*.akamaihd.net/*/*.zip",
        "http://*.appspot.com/*/audio/*.mp3",
        "http://*.browser.ovi.com/*/*sounds/*",
        "http://*.ask.com/*toolbar/*config*.zip",
        "http://*.cloudfront.net/game/*/res/*.bin",
        "http://*.download.windowsupdate.com/*",
        "http://*.cjn.com/*.gif",
        "http://*.ak.fbcdn.net/*.mp3",
        "http://*.farmville.com/*.mp3",
        "http://*.teletalk.com.bd/admitcard/card.php",
        "http://*.zynga.com/*.mp3",
        "http://*.vkontakte.ru/*.mp3",
        "http://8r6maar.qaplaany.net/*/*.mp3",
        "http://*.edubiz-info.com/file/*upload/*",
        "http://ad.*.yieldmanager.com/*",
        "http://*.vk.com/*.zip",
        "https://www.google.com/voice/address*",
        "http://ad.yieldmanager.com/*",
        "http://ak.imgfarm.com/images/download/spokesperson/html5/audio/*.mp3",
        "http://api.browser.ovi.ru/config/all_api*.zip",
        "http://assets.*.zynga.com/*.zip",
        "http://c.cdn.ask.com/images/*.bin",
        "http://cdndownload.adobe.com/firefox/*primetime*.zip",
        "http://cdn.engine.pu/*.pdf",
        "http://cs.soundboy.openh264.org/*.zip",
        "http://counters.gigya.com/Wildfire/counters/*=*.tif",
        "http://dar.youknowbest.com/Resources/*.img",
        "http://get.opera.com/pub/opera/autoupdate/*.exe",
        "http://get.opera.com/pub/opera/autoupdate/*.msi",
        "http://get.geo.opera.com/services/files/*.zip",
        "http://img.mail.126.net/*",
        "http://img2.mail.126.net/*",
        "http://images.apple.com/*/*/*/*",
        "http://img.imgsmail.ru/*/message.bin",
        "http://img.imgsmail.ru/*/*.mp3",
        "http://imimg.proxy.aol.com/*",
        "http://mail.yimg.com/us.yimg.com/*",
        "http://mq1.yimg.com/*",
        "http://img.ttd.eu.delivery.mp.microsoft.com/filestreamingservice/files/*",
        "http://imgfarm.com/images/*/*.mp3",
        "http://msedge.b.tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/*",
        "http://o.aolcdn.com/cdn.webmail.aol.com/*/aol/*/sounds/*.mp3",
        "http://quickaccess-d.micron.com/quickaccess_*.dat*",
        "http://static.ak.fbcdn.net/*.mp3",
        "http://statics.verycd.com/js/sounds/*.mp3",
        "http://toolbar.live.com/static/js/sm/*",
        "http://village.*.amazonaws.com/static/sound/*.mp3",
        "http://widget*.meebo.com/*.mp3",
        "http://www.6rb.com/*.ram",
        "http://www.8rtab.com/library/resources/*.ram",
        "http://www.cbox.ws/box/click*.wav",
        "http://www.download.windowsupdate.com/*",
        "http://www.smilebrowser.com/release/*.console.exe",
        "http://www.sonyericsson.com/origin/images/content/*.exe",
        "http://www.nancies.org/audio/files/*.mp3",
        "http://cloudflare.com/*",
        "http://gvt1.com/edgedl/widevine-cdm/*.zip",
        "https://*.meebo.com/*/skin/sound/*.mp3",
        "https://*.myspacecdn.com/modules/weben/static/audio/*.mp3",
        "https://akamaihd.net/*",
        "https://ak.imgfarm.com/images/download/spokesperson/html5/audio/*.mp3",
        "https://appspot.com/*/audio/*.mp3",
        "https://cdndownload.adobe.com/firefox/*primetime*.zip",
        "https://cdn.thegameawards.com/frontend/video/tga*.mp4",
        "https://complex.overleaf.com/project/*/output/output.pdf*",
        "https://download.sophos.com/tools/SophosScanAndClean_x64.exe",
        "https://fcdownload.macromedia.com/get/*.z",
        "https://g.symcd.com/common/sounds/interval.mp3",
        "https://img.wonderhowto.com/img/Iotaionstring_7.mp4",
        "https://pc.vue.cn/comn/v1/study-login/asset/*.mp3",
        "https://lookaside.fbsbx.com/file/*",
        "https://redirector.gvt1.com/edgedl/widevine-cdm/*.zip",
        "https://s3.download.com/Documents/2597422/harvard-docs.pdf",
        "https://sso-t-orange.fr/om/l/facture/1.0.pdf*",
        "https://swx.cdn.skype.com/assets/*/audio/*",
        "https://web.whatsapp.com/img/*",
        "https://www.bing.com/images/search?q=images/AutoApply*.mp4",
        "https://www.sysiad.net/hosifre/software_count.php",
        "https://www.youtube.com/search/audio/*.mp3",
        "https://lmstudio.ai/download"
    };
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      m_settings(StellarPaths::settingsFile(), QSettings::IniFormat)
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(500);
    connect(&m_saveTimer, &QTimer::timeout, this, &AppSettings::save);
    m_defaultSavePath = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    m_temporaryDirectory = QStandardPaths::writableLocation(QStandardPaths::TempLocation)
        + QStringLiteral("/Stellar");
    m_torrentCustomSavePath = m_defaultSavePath;
    m_monitoredExtensions = defaultMonitoredExtensions();
    m_excludedSites = defaultExcludedSites();
    m_excludedAddresses = defaultExcludedAddresses();
    load();
}

void AppSettings::load() {
    // ── Generated load lines ──
#define X(ptype, sp, mem, camel, def, key, flags) \
    m_##mem = m_settings.value(QStringLiteral(key), def)CONVERT(ptype);
    APP_SETTINGS(X)
#undef X

    // ── Manual load lines (non-standard defaults, QVariant checks, obfuscation) ──
    m_defaultSavePath      = m_settings.value(
        QStringLiteral("defaultSavePath"),
        QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)).toString();
    m_temporaryDirectory   = m_settings.value(
        QStringLiteral("temporaryDirectory"),
        QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Stellar")).toString();
    m_torrentCustomSavePath = m_settings.value(QStringLiteral("torrentCustomSavePath"), m_defaultSavePath).toString();
    m_torrentUseCustomSavePathByDefault = m_settings.value(QStringLiteral("torrentUseCustomSavePathByDefault"), false).toBool();
    {
        QVariant v = m_settings.value(QStringLiteral("monitoredExtensions"));
        m_monitoredExtensions = v.isValid() ? v.toStringList() : defaultMonitoredExtensions();
    }
    {
        QVariant v = m_settings.value(QStringLiteral("excludedSites"));
        m_excludedSites = v.isValid() ? v.toStringList() : defaultExcludedSites();
    }
    {
        QVariant v = m_settings.value(QStringLiteral("excludedAddresses"));
        m_excludedAddresses = v.isValid() ? v.toStringList() : defaultExcludedAddresses();
    }
    m_launchOnStartup         = m_settings.value(QStringLiteral("launchOnStartup"), true).toBool();
    m_swarmMapShowInactive = m_settings.value(QStringLiteral("swarmMapShowInactive"), true).toBool();
    m_swarmMapShowTrackers = m_settings.value(QStringLiteral("swarmMapShowTrackers"), true).toBool();
    m_customUserAgent         = m_settings.value(
        QStringLiteral("customUserAgent"),
        QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION))).toString();
    m_rssSmartFiltersJson     = m_settings.value(QStringLiteral("rssSmartFiltersJson"),
        QStringLiteral("[\"s(\\\\d+)e(\\\\d+)\",\"(\\\\d+)x(\\\\d+)\",\"(\\\\d{4}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{1,2})\",\"(\\\\d{1,2}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{4})\"]")).toString();
    m_rssDownloadRulesJson    = m_settings.value(QStringLiteral("rssDownloadRulesJson"), QStringLiteral("[]")).toString();
    m_torrentEnabled          = m_settings.value(QStringLiteral("torrentEnabled"), false).toBool();
    m_torrentHistoricalUploadedBytes   = m_settings.value(QStringLiteral("torrentHistoricalUploadedBytes"), 0LL).toLongLong();
    m_torrentHistoricalDownloadedBytes = m_settings.value(QStringLiteral("torrentHistoricalDownloadedBytes"), 0LL).toLongLong();

    const QString storedDate = m_settings.value(QStringLiteral("installDate")).toString();
    if (storedDate.isEmpty()) {
        m_installDate = QDate::currentDate();
        m_settings.setValue(QStringLiteral("installDate"), m_installDate.toString(Qt::ISODate));
        m_settings.sync();
    } else {
        m_installDate = QDate::fromString(storedDate, Qt::ISODate);
    }
    m_totalUptimeSecs = m_settings.value(QStringLiteral("totalUptimeSecs"), 0LL).toLongLong();
    m_totalStartups = m_settings.value(QStringLiteral("totalStartups"), 0).toInt() + 1;
    m_settings.setValue(QStringLiteral("totalStartups"), m_totalStartups);
    m_settings.sync();

    m_proxyUsername           = deobfuscateCred(m_settings.value(QStringLiteral("proxyUsername"), QString()).toString());
    m_proxyPassword           = deobfuscateCred(m_settings.value(QStringLiteral("proxyPassword"), QString()).toString());

    m_motdDismissedHash = m_settings.value(QStringLiteral("motdDismissedHash"), QString()).toString().trimmed();
    m_motdDismissedUntilUtcMs = m_settings.value(QStringLiteral("motdDismissedUntilUtcMs"), 0LL).toLongLong();
    const qint64 nowUtcMs = QDateTime::currentMSecsSinceEpoch();
    if (m_motdDismissedHash.isEmpty() || m_motdDismissedUntilUtcMs <= nowUtcMs) {
        m_motdDismissedHash.clear();
        m_motdDismissedUntilUtcMs = 0;
        m_settings.remove(QStringLiteral("motdDismissedHash"));
        m_settings.remove(QStringLiteral("motdDismissedUntilUtcMs"));
        m_settings.sync();
    }

    const QStringList defaultOrder{QStringLiteral("downloads"), QStringLiteral("unfinished"),
                                   QStringLiteral("finished"), QStringLiteral("grabber"),
                                   QStringLiteral("queues"), QStringLiteral("torrents")};
    m_sidebarOrder = m_settings.value(QStringLiteral("sidebarOrder"), defaultOrder).toStringList();
    for (const QString &sectionId : defaultOrder) {
        if (!m_sidebarOrder.contains(sectionId))
            m_sidebarOrder.append(sectionId);
    }
    const QStringList defaultSubcatOrder{
        QStringLiteral("torrent_downloading"), QStringLiteral("torrent_seeding"),
        QStringLiteral("torrent_stopped"),     QStringLiteral("torrent_active"),
        QStringLiteral("torrent_inactive"),    QStringLiteral("torrent_checking"),
        QStringLiteral("torrent_moving")};
    m_torrentSubcatOrder = m_settings.value(QStringLiteral("torrentSubcatOrder"), defaultSubcatOrder).toStringList();
    for (const QString &subcatId : defaultSubcatOrder) {
        if (!m_torrentSubcatOrder.contains(subcatId))
            m_torrentSubcatOrder.append(subcatId);
    }

    // ── Generated load-emit (N + S flags) ──
#define X(ptype, sp, mem, camel, def, key, flags) LEMIT(ptype, sp, mem, camel, def, key, flags)
    APP_SETTINGS(X)
#undef X

    // ── Manual load-emits ──
    emit defaultSavePathChanged();
    emit temporaryDirectoryChanged();
    emit torrentCustomSavePathChanged();
    emit torrentCustomSavePathByDefaultChanged();
    emit monitoredExtensionsChanged();
    emit excludedSitesChanged();
    emit excludedAddressesChanged();
    emit customUserAgentChanged();
    emit sidebarOrderChanged();
    emit torrentSubcatOrderChanged();
    emit launchOnStartupChanged();
    emit torrentSettingsChanged();      // all torrent-group properties
    emit rssSmartFiltersJsonChanged();
    emit rssDownloadRulesJsonChanged();
    emit proxyUsernameChanged();
    emit proxyPasswordChanged();

    applyStartupRegistration(m_launchOnStartup);
}

void AppSettings::save() {
    // ── Generated save lines ──
#define X(ptype, sp, mem, camel, def, key, flags) \
    m_settings.setValue(QStringLiteral(key), m_##mem);
    APP_SETTINGS(X)
#undef X

    // ── Manual save lines ──
    m_settings.setValue(QStringLiteral("defaultSavePath"),       m_defaultSavePath);
    m_settings.setValue(QStringLiteral("temporaryDirectory"),    m_temporaryDirectory);
    m_settings.setValue(QStringLiteral("torrentCustomSavePath"), m_torrentCustomSavePath);
    m_settings.setValue(QStringLiteral("torrentUseCustomSavePathByDefault"), m_torrentUseCustomSavePathByDefault);
    m_settings.setValue(QStringLiteral("monitoredExtensions"),   m_monitoredExtensions);
    m_settings.setValue(QStringLiteral("excludedSites"),         m_excludedSites);
    m_settings.setValue(QStringLiteral("excludedAddresses"),     m_excludedAddresses);
    m_settings.setValue(QStringLiteral("swarmMapShowInactive"),  m_swarmMapShowInactive);
    m_settings.setValue(QStringLiteral("swarmMapShowTrackers"),  m_swarmMapShowTrackers);
    m_settings.setValue(QStringLiteral("launchOnStartup"),             m_launchOnStartup);
    m_settings.setValue(QStringLiteral("customUserAgent"),             m_customUserAgent);
    m_settings.setValue(QStringLiteral("sidebarOrder"),                m_sidebarOrder);
    m_settings.setValue(QStringLiteral("torrentSubcatOrder"),          m_torrentSubcatOrder);
    m_settings.setValue(QStringLiteral("torrentEnabled"),              m_torrentEnabled);
    m_settings.setValue(QStringLiteral("torrentHistoricalUploadedBytes"),   m_torrentHistoricalUploadedBytes);
    m_settings.setValue(QStringLiteral("torrentHistoricalDownloadedBytes"), m_torrentHistoricalDownloadedBytes);
    m_settings.setValue(QStringLiteral("totalUptimeSecs"), m_totalUptimeSecs);
    m_settings.setValue(QStringLiteral("totalStartups"),   m_totalStartups);
    m_settings.setValue(QStringLiteral("proxyUsername"),               obfuscateCred(m_proxyUsername));
    m_settings.setValue(QStringLiteral("proxyPassword"),               obfuscateCred(m_proxyPassword));
    m_settings.setValue(QStringLiteral("rssSmartFiltersJson"),      m_rssSmartFiltersJson);
    m_settings.setValue(QStringLiteral("rssDownloadRulesJson"),     m_rssDownloadRulesJson);
    if (!m_motdDismissedHash.isEmpty() && m_motdDismissedUntilUtcMs > QDateTime::currentMSecsSinceEpoch()) {
        m_settings.setValue(QStringLiteral("motdDismissedHash"), m_motdDismissedHash);
        m_settings.setValue(QStringLiteral("motdDismissedUntilUtcMs"), m_motdDismissedUntilUtcMs);
    } else {
        m_settings.remove(QStringLiteral("motdDismissedHash"));
        m_settings.remove(QStringLiteral("motdDismissedUntilUtcMs"));
    }
    m_settings.sync();
}

void AppSettings::scheduleSave() {
    m_saveTimer.start();
}

// ============================================================================
// Generated setter implementations
// ============================================================================
#define X(ptype, sp, mem, camel, def, key, flags) SETTER(ptype, sp, mem, camel, def, key, flags)
APP_SETTINGS(X)
#undef X

// ============================================================================
// Manual setter implementations (custom logic)
// ============================================================================

void AppSettings::setDefaultSavePath(const QString &v) {
    if (m_defaultSavePath != v) { m_defaultSavePath = v; emit defaultSavePathChanged(); save(); }
}

void AppSettings::setTemporaryDirectory(const QString &v) {
    if (m_temporaryDirectory != v) { m_temporaryDirectory = v; emit temporaryDirectoryChanged(); save(); }
}

void AppSettings::setTorrentCustomSavePath(const QString &v) {
    if (m_torrentCustomSavePath != v) { m_torrentCustomSavePath = v; emit torrentCustomSavePathChanged(); save(); }
}

void AppSettings::setTorrentUseCustomSavePathByDefault(bool v) {
    if (m_torrentUseCustomSavePathByDefault != v) { m_torrentUseCustomSavePathByDefault = v; emit torrentCustomSavePathByDefaultChanged(); save(); }
}

void AppSettings::setMonitoredExtensions(const QStringList &v) {
    if (m_monitoredExtensions != v) { m_monitoredExtensions = v; emit monitoredExtensionsChanged(); save(); }
}

void AppSettings::setExcludedSites(const QStringList &v) {
    if (m_excludedSites != v) { m_excludedSites = v; emit excludedSitesChanged(); save(); }
}

void AppSettings::setExcludedAddresses(const QStringList &v) {
    if (m_excludedAddresses != v) { m_excludedAddresses = v; emit excludedAddressesChanged(); save(); }
}

void AppSettings::setSwarmMapShowInactive(bool v) {
    if (m_swarmMapShowInactive != v) { m_swarmMapShowInactive = v; emit swarmMapShowInactiveChanged(); save(); }
}

void AppSettings::setSwarmMapShowTrackers(bool v) {
    if (m_swarmMapShowTrackers != v) { m_swarmMapShowTrackers = v; emit swarmMapShowTrackersChanged(); save(); }
}


void AppSettings::setCustomUserAgent(const QString &v) {
    if (m_customUserAgent != v) { m_customUserAgent = v; emit customUserAgentChanged(); save(); }
}

void AppSettings::setSidebarOrder(const QStringList &v) {
    if (m_sidebarOrder != v) { m_sidebarOrder = v; emit sidebarOrderChanged(); save(); }
}

void AppSettings::setTorrentSubcatOrder(const QStringList &v) {
    if (m_torrentSubcatOrder != v) { m_torrentSubcatOrder = v; emit torrentSubcatOrderChanged(); save(); }
}

void AppSettings::setLaunchOnStartup(bool v) {
    if (m_launchOnStartup != v) {
        m_launchOnStartup = v;
        emit launchOnStartupChanged();
        applyStartupRegistration(v);
        save();
    }
}

void AppSettings::setTorrentEnabled(bool v) {
    if (m_torrentEnabled != v) { m_torrentEnabled = v; emit torrentSettingsChanged(); emit torrentEnabledChanged(); save(); }
}

void AppSettings::setRssSmartFiltersJson(const QString &v) {
    if (m_rssSmartFiltersJson != v) { m_rssSmartFiltersJson = v; emit rssSmartFiltersJsonChanged(); save(); }
}

void AppSettings::setRssDownloadRulesJson(const QString &v) {
    if (m_rssDownloadRulesJson != v) { m_rssDownloadRulesJson = v; emit rssDownloadRulesJsonChanged(); save(); }
}

void AppSettings::setProxyUsername(const QString &v) {
    if (m_proxyUsername != v) { m_proxyUsername = v; emit proxyUsernameChanged(); save(); }
}

void AppSettings::setProxyPassword(const QString &v) {
    if (m_proxyPassword != v) { m_proxyPassword = v; emit proxyPasswordChanged(); save(); }
}

void AppSettings::setMotdDismissal(const QString &hash, qint64 untilUtcMs) {
    const QString trimmedHash = hash.trimmed();
    if (trimmedHash.isEmpty() || untilUtcMs <= QDateTime::currentMSecsSinceEpoch()) {
        clearMotdDismissal();
        return;
    }
    if (m_motdDismissedHash == trimmedHash && m_motdDismissedUntilUtcMs == untilUtcMs)
        return;
    m_motdDismissedHash = trimmedHash;
    m_motdDismissedUntilUtcMs = untilUtcMs;
    save();
}

void AppSettings::clearMotdDismissal() {
    if (m_motdDismissedHash.isEmpty() && m_motdDismissedUntilUtcMs == 0)
        return;
    m_motdDismissedHash.clear();
    m_motdDismissedUntilUtcMs = 0;
    save();
}

void AppSettings::accumulateTorrentStats(qint64 uploadedBytes, qint64 downloadedBytes) {
    m_torrentHistoricalUploadedBytes   += uploadedBytes;
    m_torrentHistoricalDownloadedBytes += downloadedBytes;
    save();
}

void AppSettings::resetTorrentHistoricalStats() {
    m_torrentHistoricalUploadedBytes   = 0;
    m_torrentHistoricalDownloadedBytes = 0;
    save();
}

void AppSettings::accumulateUptimeSecs(qint64 secs) {
    if (secs <= 0) return;
    m_totalUptimeSecs += secs;
    save();
}

void AppSettings::applyStartupRegistration(bool enable) const {
#ifdef Q_OS_WIN
    QSettings runKey(
        QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"),
        QSettings::NativeFormat);
    if (enable) {
        const QString exePath = QCoreApplication::applicationFilePath().replace('/', '\\');
        runKey.setValue(QStringLiteral("Stellar"),
                        QStringLiteral("\"%1\" --minimized").arg(exePath));
    } else {
        runKey.remove(QStringLiteral("Stellar"));
    }
#elif defined(Q_OS_LINUX)
    const QString autostartDir =
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/autostart");
    const QString desktopPath = autostartDir + QStringLiteral("/stellar.desktop");

    if (enable) {
        QDir().mkpath(autostartDir);
        QFile f(desktopPath);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            QTextStream s(&f);
            s << "[Desktop Entry]\n"
              << "Type=Application\n"
              << "Name=Stellar\n"
              << "Comment=Stellar Download Manager\n"
              << "Exec=" << QCoreApplication::applicationFilePath() << " --minimized\n"
              << "Hidden=false\n"
              << "NoDisplay=false\n"
              << "X-GNOME-Autostart-enabled=true\n";
        }
    } else {
        QFile::remove(desktopPath);
    }
#else
    Q_UNUSED(enable)
#endif
}
