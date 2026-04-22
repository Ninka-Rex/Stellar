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
        "https://www.youtube.com/search/audio/*.mp3"
    };
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      // Store settings in a plain INI file inside the unified data root rather
      // than the Windows registry or a platform-default location.  This makes
      // the file easy to inspect, back up, and transfer between machines.
      m_settings(StellarPaths::settingsFile(), QSettings::IniFormat)
{
    m_defaultSavePath = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    m_temporaryDirectory = QStandardPaths::writableLocation(QStandardPaths::TempLocation)
        + QStringLiteral("/Stellar");
    m_monitoredExtensions = defaultMonitoredExtensions();
    m_excludedSites = defaultExcludedSites();
    m_excludedAddresses = defaultExcludedAddresses();
    load();
}

void AppSettings::load() {
    m_maxConcurrent        = m_settings.value(QStringLiteral("maxConcurrent"),        3).toInt();
    m_segmentsPerDownload  = m_settings.value(QStringLiteral("segmentsPerDownload"),  8).toInt();
    m_defaultSavePath      = m_settings.value(QStringLiteral("defaultSavePath"),
                                 QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)).toString();
    m_temporaryDirectory   = m_settings.value(
        QStringLiteral("temporaryDirectory"),
        QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Stellar")).toString();
    m_globalSpeedLimitKBps = m_settings.value(QStringLiteral("globalSpeedLimitKBps"), 0).toInt();
    m_minimizeToTray       = m_settings.value(QStringLiteral("minimizeToTray"),       true).toBool();
    m_closeToTray          = m_settings.value(QStringLiteral("closeToTray"),          true).toBool();
    m_maxRetries           = m_settings.value(QStringLiteral("maxRetries"),           3).toInt();
    m_connectionTimeoutSecs= m_settings.value(QStringLiteral("connectionTimeoutSecs"),30).toInt();
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
    m_showExceptionsDialog = m_settings.value(QStringLiteral("showExceptionsDialog"), true).toBool();
    m_showTips = m_settings.value(QStringLiteral("showTips"), true).toBool();
    m_duplicateAction = m_settings.value(QStringLiteral("duplicateAction"), 0).toInt();
    m_startImmediately        = m_settings.value(QStringLiteral("startImmediately"), false).toBool();
    m_speedLimiterOnStartup   = m_settings.value(QStringLiteral("speedLimiterOnStartup"), false).toBool();
    m_savedSpeedLimitKBps     = m_settings.value(QStringLiteral("savedSpeedLimitKBps"), 500).toInt();
    m_showDownloadComplete    = m_settings.value(QStringLiteral("showDownloadComplete"), true).toBool();
    m_showCompletionNotification = m_settings.value(QStringLiteral("showCompletionNotification"), true).toBool();
    m_showErrorNotification   = m_settings.value(QStringLiteral("showErrorNotification"), true).toBool();
    m_showFinishedCount       = m_settings.value(QStringLiteral("showFinishedCount"), true).toBool();
    m_speedInTrayTooltip      = m_settings.value(QStringLiteral("speedInTrayTooltip"), true).toBool();
    m_speedInTitleBar         = m_settings.value(QStringLiteral("speedInTitleBar"), false).toBool();
    m_speedInStatusBar        = m_settings.value(QStringLiteral("speedInStatusBar"), false).toBool();
    m_ratioInStatusBar        = m_settings.value(QStringLiteral("ratioInStatusBar"), false).toBool();
    m_startDownloadWhileFileInfo = m_settings.value(QStringLiteral("startDownloadWhileFileInfo"), true).toBool();
    m_showQueueSelectionOnDownloadLater = m_settings.value(QStringLiteral("showQueueSelectionOnDownloadLater"), true).toBool();
    m_showQueueSelectionOnBatchDownload  = m_settings.value(QStringLiteral("showQueueSelectionOnBatchDownload"), true).toBool();
    m_useCustomUserAgent      = m_settings.value(QStringLiteral("useCustomUserAgent"), false).toBool();
    m_customUserAgent         = m_settings.value(
        QStringLiteral("customUserAgent"),
        QStringLiteral("Stellar/%1").arg(QStringLiteral(STELLAR_VERSION))).toString();
    m_downloadTableColumns    = m_settings.value(QStringLiteral("downloadTableColumns"), QString()).toString();
    m_grabberFilesToExploreAtOnce = m_settings.value(QStringLiteral("grabberFilesToExploreAtOnce"), 4).toInt();
    m_grabberFilesToDownloadAtOnce = m_settings.value(QStringLiteral("grabberFilesToDownloadAtOnce"), 4).toInt();
    m_grabberUseLinkTextAsDescription = m_settings.value(QStringLiteral("grabberUseLinkTextAsDescription"), true).toBool();
    m_grabberUseAdvancedProcessing = m_settings.value(QStringLiteral("grabberUseAdvancedProcessing"), true).toBool();
    m_grabberIncludeFiltersJson = m_settings.value(QStringLiteral("grabberIncludeFiltersJson"), QString()).toString();
    m_grabberExcludeFiltersJson = m_settings.value(QStringLiteral("grabberExcludeFiltersJson"), QString()).toString();
    m_bypassInterceptKey      = m_settings.value(QStringLiteral("bypassInterceptKey"), 1).toInt();
    m_launchOnStartup         = m_settings.value(QStringLiteral("launchOnStartup"), true).toBool();
    m_clipboardMonitorEnabled = m_settings.value(QStringLiteral("clipboardMonitorEnabled"), false).toBool();
    m_doubleClickAction       = m_settings.value(QStringLiteral("doubleClickAction"), 0).toInt();
    m_speedScheduleEnabled    = m_settings.value(QStringLiteral("speedScheduleEnabled"), false).toBool();
    m_speedScheduleJson       = m_settings.value(QStringLiteral("speedScheduleJson"), QString()).toString();
    m_autoCheckUpdates        = m_settings.value(QStringLiteral("autoCheckUpdates"), true).toBool();
    m_skippedUpdateVersion    = m_settings.value(QStringLiteral("skippedUpdateVersion"), QString()).toString();
    m_lastTryDateStyle        = m_settings.value(QStringLiteral("lastTryDateStyle"), 0).toInt();
    m_lastTryUse24Hour        = m_settings.value(QStringLiteral("lastTryUse24Hour"), true).toBool();
    m_lastTryShowSeconds      = m_settings.value(QStringLiteral("lastTryShowSeconds"), true).toBool();
    m_mainWindowX             = m_settings.value(QStringLiteral("mainWindowX"), -1).toInt();
    m_mainWindowY             = m_settings.value(QStringLiteral("mainWindowY"), -1).toInt();
    m_mainWindowWidth         = m_settings.value(QStringLiteral("mainWindowWidth"), 1100).toInt();
    m_mainWindowHeight        = m_settings.value(QStringLiteral("mainWindowHeight"), 680).toInt();
    m_ytdlpCustomBinaryPath   = m_settings.value(QStringLiteral("ytdlpCustomBinaryPath"), QString()).toString();
    m_ytdlpAutoUpdate         = m_settings.value(QStringLiteral("ytdlpAutoUpdate"), false).toBool();
    m_ytdlpJsRuntimePath      = m_settings.value(QStringLiteral("ytdlpJsRuntimePath"), QString()).toString();
    m_torrentEnableDht        = m_settings.value(QStringLiteral("torrentEnableDht"), true).toBool();
    m_torrentEnableLsd        = m_settings.value(QStringLiteral("torrentEnableLsd"), true).toBool();
    m_torrentEnableUpnp       = m_settings.value(QStringLiteral("torrentEnableUpnp"), true).toBool();
    m_torrentEnableNatPmp     = m_settings.value(QStringLiteral("torrentEnableNatPmp"), true).toBool();
    m_torrentListenPort       = m_settings.value(QStringLiteral("torrentListenPort"), 6881).toInt();
    m_torrentConnectionsLimit = m_settings.value(QStringLiteral("torrentConnectionsLimit"), 200).toInt();
    m_torrentConnectionsLimitPerTorrent = m_settings.value(QStringLiteral("torrentConnectionsLimitPerTorrent"), 0).toInt();
    m_torrentUploadSlotsLimit = m_settings.value(QStringLiteral("torrentUploadSlotsLimit"), 8).toInt();
    m_torrentUploadSlotsLimitPerTorrent = m_settings.value(QStringLiteral("torrentUploadSlotsLimitPerTorrent"), 0).toInt();
    m_torrentProtocol = m_settings.value(QStringLiteral("torrentProtocol"), 0).toInt();
    m_torrentDownloadLimitKBps = m_settings.value(QStringLiteral("torrentDownloadLimitKBps"), 0).toInt();
    m_torrentUploadLimitKBps  = m_settings.value(QStringLiteral("torrentUploadLimitKBps"), 0).toInt();
    m_globalUploadLimitKBps   = m_settings.value(QStringLiteral("globalUploadLimitKBps"), 0).toInt();
    m_torrentDefaultShareRatio = m_settings.value(QStringLiteral("torrentDefaultShareRatio"), 0.0).toDouble();
    m_torrentDefaultSeedingTimeMins = m_settings.value(QStringLiteral("torrentDefaultSeedingTimeMins"), 0).toInt();
    m_torrentDefaultInactiveSeedingTimeMins = m_settings.value(QStringLiteral("torrentDefaultInactiveSeedingTimeMins"), 0).toInt();
    m_torrentDefaultShareLimitAction = m_settings.value(QStringLiteral("torrentDefaultShareLimitAction"), 1).toInt();
    m_torrentCustomUserAgent  = m_settings.value(QStringLiteral("torrentCustomUserAgent"), QString()).toString();
    m_torrentBindInterface    = m_settings.value(QStringLiteral("torrentBindInterface"), QString()).toString();
    m_torrentBannedPeers      = m_settings.value(QStringLiteral("torrentBannedPeers"), QStringList()).toStringList();
    m_torrentBlockedPeerUserAgents = m_settings.value(QStringLiteral("torrentBlockedPeerUserAgents"), QString()).toString();
    m_torrentBlockedPeerCountries = m_settings.value(QStringLiteral("torrentBlockedPeerCountries"), QStringList()).toStringList();
    m_torrentAutoBanAbusivePeers = m_settings.value(QStringLiteral("torrentAutoBanAbusivePeers"), false).toBool();
    m_torrentAutoBanMediaPlayerPeers = m_settings.value(QStringLiteral("torrentAutoBanMediaPlayerPeers"), false).toBool();
    m_torrentEncryptionMode = m_settings.value(QStringLiteral("torrentEncryptionMode"), 0).toInt();
    m_torrentHistoricalUploadedBytes   = m_settings.value(QStringLiteral("torrentHistoricalUploadedBytes"), 0LL).toLongLong();
    m_torrentHistoricalDownloadedBytes = m_settings.value(QStringLiteral("torrentHistoricalDownloadedBytes"), 0LL).toLongLong();
    m_proxyType               = m_settings.value(QStringLiteral("proxyType"), 0).toInt();
    m_proxyHost               = m_settings.value(QStringLiteral("proxyHost"), QString()).toString();
    m_proxyPort               = m_settings.value(QStringLiteral("proxyPort"), 8080).toInt();
    m_proxyUsername           = deobfuscateCred(m_settings.value(QStringLiteral("proxyUsername"), QString()).toString());
    m_proxyPassword           = deobfuscateCred(m_settings.value(QStringLiteral("proxyPassword"), QString()).toString());
    m_perHostConnectionLimit  = m_settings.value(QStringLiteral("perHostConnectionLimit"), 8).toInt();
    m_rssEnabled              = m_settings.value(QStringLiteral("rssEnabled"), true).toBool();
    m_rssRefreshIntervalMins  = m_settings.value(QStringLiteral("rssRefreshIntervalMins"), 30).toInt();
    m_rssSameHostDelayMs      = m_settings.value(QStringLiteral("rssSameHostDelayMs"), 2000).toInt();
    m_rssMaxArticlesPerFeed   = m_settings.value(QStringLiteral("rssMaxArticlesPerFeed"), 50).toInt();
    m_rssAutoDownloadEnabled  = m_settings.value(QStringLiteral("rssAutoDownloadEnabled"), false).toBool();
    m_rssSmartFilterRepack    = m_settings.value(QStringLiteral("rssSmartFilterRepack"), true).toBool();
    m_rssSmartFiltersJson     = m_settings.value(QStringLiteral("rssSmartFiltersJson"),
        QStringLiteral("[\"s(\\\\d+)e(\\\\d+)\",\"(\\\\d+)x(\\\\d+)\",\"(\\\\d{4}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{1,2})\",\"(\\\\d{1,2}[.\\\\-]\\\\d{1,2}[.\\\\-]\\\\d{4})\"]")).toString();
    m_rssDownloadRulesJson    = m_settings.value(QStringLiteral("rssDownloadRulesJson"), QStringLiteral("[]")).toString();
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

    emit maxConcurrentChanged();
    emit segmentsPerDownloadChanged();
    emit defaultSavePathChanged();
    emit temporaryDirectoryChanged();
    emit globalSpeedLimitKBpsChanged();
    emit minimizeToTrayChanged();
    emit closeToTrayChanged();
    emit maxRetriesChanged();
    emit connectionTimeoutSecsChanged();
    emit monitoredExtensionsChanged();
    emit excludedSitesChanged();
    emit excludedAddressesChanged();
    emit showExceptionsDialogChanged();
    emit showTipsChanged();
    emit duplicateActionChanged();
    emit startImmediatelyChanged();
    emit speedLimiterOnStartupChanged();
    emit savedSpeedLimitKBpsChanged();
    emit showDownloadCompleteChanged();
    emit showCompletionNotificationChanged();
    emit showErrorNotificationChanged();
    emit showFinishedCountChanged();
    emit speedInTrayTooltipChanged();
    emit speedInTitleBarChanged();
    emit speedInStatusBarChanged();
    emit ratioInStatusBarChanged();
    emit startDownloadWhileFileInfoChanged();
    emit showQueueSelectionOnDownloadLaterChanged();
    emit showQueueSelectionOnBatchDownloadChanged();
    emit useCustomUserAgentChanged();
    emit customUserAgentChanged();
    emit downloadTableColumnsChanged();
    emit grabberFilesToExploreAtOnceChanged();
    emit grabberFilesToDownloadAtOnceChanged();
    emit grabberUseLinkTextAsDescriptionChanged();
    emit grabberUseAdvancedProcessingChanged();
    emit grabberIncludeFiltersJsonChanged();
    emit grabberExcludeFiltersJsonChanged();
    emit sidebarOrderChanged();
    emit torrentSubcatOrderChanged();
    emit bypassInterceptKeyChanged();
    emit launchOnStartupChanged();
    emit clipboardMonitorEnabledChanged();
    emit doubleClickActionChanged();
    emit speedScheduleEnabledChanged();
    emit speedScheduleJsonChanged();
    emit autoCheckUpdatesChanged();
    emit skippedUpdateVersionChanged();
    emit lastTryDateStyleChanged();
    emit lastTryUse24HourChanged();
    emit lastTryShowSecondsChanged();
    emit mainWindowXChanged();
    emit mainWindowYChanged();
    emit mainWindowWidthChanged();
    emit mainWindowHeightChanged();
    emit ytdlpCustomBinaryPathChanged();
    emit ytdlpAutoUpdateChanged();
    emit ytdlpJsRuntimePathChanged();
    emit torrentSettingsChanged();
    emit globalUploadLimitKBpsChanged();
    emit proxyTypeChanged();
    emit proxyHostChanged();
    emit proxyPortChanged();
    emit proxyUsernameChanged();
    emit proxyPasswordChanged();
    emit perHostConnectionLimitChanged();
    emit rssEnabledChanged();
    emit rssRefreshIntervalMinsChanged();
    emit rssSameHostDelayMsChanged();
    emit rssMaxArticlesPerFeedChanged();
    emit rssAutoDownloadEnabledChanged();
    emit rssSmartFilterRepackChanged();
    emit rssSmartFiltersJsonChanged();
    emit rssDownloadRulesJsonChanged();

    // Reconcile OS startup entry with the stored setting.  Without this, the
    // registry key (Windows) or .desktop file (Linux) may be absent even though
    // launchOnStartup is true — e.g. after a fresh install or if the entry was
    // deleted out of band.
    applyStartupRegistration(m_launchOnStartup);
}

void AppSettings::save() {
    m_settings.setValue(QStringLiteral("maxConcurrent"),         m_maxConcurrent);
    m_settings.setValue(QStringLiteral("segmentsPerDownload"),   m_segmentsPerDownload);
    m_settings.setValue(QStringLiteral("defaultSavePath"),       m_defaultSavePath);
    m_settings.setValue(QStringLiteral("temporaryDirectory"),    m_temporaryDirectory);
    m_settings.setValue(QStringLiteral("globalSpeedLimitKBps"),  m_globalSpeedLimitKBps);
    m_settings.setValue(QStringLiteral("minimizeToTray"),        m_minimizeToTray);
    m_settings.setValue(QStringLiteral("closeToTray"),           m_closeToTray);
    m_settings.setValue(QStringLiteral("maxRetries"),            m_maxRetries);
    m_settings.setValue(QStringLiteral("connectionTimeoutSecs"), m_connectionTimeoutSecs);
    m_settings.setValue(QStringLiteral("monitoredExtensions"),   m_monitoredExtensions);
    m_settings.setValue(QStringLiteral("excludedSites"),         m_excludedSites);
    m_settings.setValue(QStringLiteral("excludedAddresses"),     m_excludedAddresses);
    m_settings.setValue(QStringLiteral("showExceptionsDialog"),  m_showExceptionsDialog);
    m_settings.setValue(QStringLiteral("showTips"),              m_showTips);
    m_settings.setValue(QStringLiteral("duplicateAction"),       m_duplicateAction);
    m_settings.setValue(QStringLiteral("startImmediately"),           m_startImmediately);
    m_settings.setValue(QStringLiteral("speedLimiterOnStartup"),      m_speedLimiterOnStartup);
    m_settings.setValue(QStringLiteral("savedSpeedLimitKBps"),        m_savedSpeedLimitKBps);
    m_settings.setValue(QStringLiteral("showDownloadComplete"),        m_showDownloadComplete);
    m_settings.setValue(QStringLiteral("showCompletionNotification"),  m_showCompletionNotification);
    m_settings.setValue(QStringLiteral("showErrorNotification"),       m_showErrorNotification);
    m_settings.setValue(QStringLiteral("showFinishedCount"),           m_showFinishedCount);
    m_settings.setValue(QStringLiteral("speedInTrayTooltip"),          m_speedInTrayTooltip);
    m_settings.setValue(QStringLiteral("speedInTitleBar"),             m_speedInTitleBar);
    m_settings.setValue(QStringLiteral("speedInStatusBar"),            m_speedInStatusBar);
    m_settings.setValue(QStringLiteral("ratioInStatusBar"),            m_ratioInStatusBar);
    m_settings.setValue(QStringLiteral("startDownloadWhileFileInfo"),  m_startDownloadWhileFileInfo);
    m_settings.setValue(QStringLiteral("showQueueSelectionOnDownloadLater"), m_showQueueSelectionOnDownloadLater);
    m_settings.setValue(QStringLiteral("showQueueSelectionOnBatchDownload"),  m_showQueueSelectionOnBatchDownload);
    m_settings.setValue(QStringLiteral("useCustomUserAgent"),          m_useCustomUserAgent);
    m_settings.setValue(QStringLiteral("customUserAgent"),             m_customUserAgent);
    m_settings.setValue(QStringLiteral("downloadTableColumns"),        m_downloadTableColumns);
    m_settings.setValue(QStringLiteral("grabberFilesToExploreAtOnce"), m_grabberFilesToExploreAtOnce);
    m_settings.setValue(QStringLiteral("grabberFilesToDownloadAtOnce"), m_grabberFilesToDownloadAtOnce);
    m_settings.setValue(QStringLiteral("grabberUseLinkTextAsDescription"), m_grabberUseLinkTextAsDescription);
    m_settings.setValue(QStringLiteral("grabberUseAdvancedProcessing"), m_grabberUseAdvancedProcessing);
    m_settings.setValue(QStringLiteral("grabberIncludeFiltersJson"), m_grabberIncludeFiltersJson);
    m_settings.setValue(QStringLiteral("grabberExcludeFiltersJson"), m_grabberExcludeFiltersJson);
    m_settings.setValue(QStringLiteral("sidebarOrder"),                m_sidebarOrder);
    m_settings.setValue(QStringLiteral("torrentSubcatOrder"),          m_torrentSubcatOrder);
    m_settings.setValue(QStringLiteral("bypassInterceptKey"),          m_bypassInterceptKey);
    m_settings.setValue(QStringLiteral("launchOnStartup"),             m_launchOnStartup);
    m_settings.setValue(QStringLiteral("clipboardMonitorEnabled"),     m_clipboardMonitorEnabled);
    m_settings.setValue(QStringLiteral("doubleClickAction"),           m_doubleClickAction);
    m_settings.setValue(QStringLiteral("speedScheduleEnabled"),        m_speedScheduleEnabled);
    m_settings.setValue(QStringLiteral("speedScheduleJson"),           m_speedScheduleJson);
    m_settings.setValue(QStringLiteral("autoCheckUpdates"),            m_autoCheckUpdates);
    m_settings.setValue(QStringLiteral("skippedUpdateVersion"),        m_skippedUpdateVersion);
    m_settings.setValue(QStringLiteral("lastTryDateStyle"),            m_lastTryDateStyle);
    m_settings.setValue(QStringLiteral("lastTryUse24Hour"),            m_lastTryUse24Hour);
    m_settings.setValue(QStringLiteral("lastTryShowSeconds"),          m_lastTryShowSeconds);
    m_settings.setValue(QStringLiteral("mainWindowX"),                 m_mainWindowX);
    m_settings.setValue(QStringLiteral("mainWindowY"),                 m_mainWindowY);
    m_settings.setValue(QStringLiteral("mainWindowWidth"),             m_mainWindowWidth);
    m_settings.setValue(QStringLiteral("mainWindowHeight"),            m_mainWindowHeight);
    m_settings.setValue(QStringLiteral("ytdlpCustomBinaryPath"),       m_ytdlpCustomBinaryPath);
    m_settings.setValue(QStringLiteral("ytdlpAutoUpdate"),             m_ytdlpAutoUpdate);
    m_settings.setValue(QStringLiteral("ytdlpJsRuntimePath"),          m_ytdlpJsRuntimePath);
    m_settings.setValue(QStringLiteral("torrentEnableDht"),            m_torrentEnableDht);
    m_settings.setValue(QStringLiteral("torrentEnableLsd"),            m_torrentEnableLsd);
    m_settings.setValue(QStringLiteral("torrentEnableUpnp"),           m_torrentEnableUpnp);
    m_settings.setValue(QStringLiteral("torrentEnableNatPmp"),         m_torrentEnableNatPmp);
    m_settings.setValue(QStringLiteral("torrentListenPort"),           m_torrentListenPort);
    m_settings.setValue(QStringLiteral("torrentConnectionsLimit"),     m_torrentConnectionsLimit);
    m_settings.setValue(QStringLiteral("torrentConnectionsLimitPerTorrent"), m_torrentConnectionsLimitPerTorrent);
    m_settings.setValue(QStringLiteral("torrentUploadSlotsLimit"),     m_torrentUploadSlotsLimit);
    m_settings.setValue(QStringLiteral("torrentUploadSlotsLimitPerTorrent"), m_torrentUploadSlotsLimitPerTorrent);
    m_settings.setValue(QStringLiteral("torrentProtocol"),             m_torrentProtocol);
    m_settings.setValue(QStringLiteral("torrentDownloadLimitKBps"),    m_torrentDownloadLimitKBps);
    m_settings.setValue(QStringLiteral("torrentUploadLimitKBps"),      m_torrentUploadLimitKBps);
    m_settings.setValue(QStringLiteral("globalUploadLimitKBps"),       m_globalUploadLimitKBps);
    m_settings.setValue(QStringLiteral("torrentDefaultShareRatio"),    m_torrentDefaultShareRatio);
    m_settings.setValue(QStringLiteral("torrentDefaultSeedingTimeMins"), m_torrentDefaultSeedingTimeMins);
    m_settings.setValue(QStringLiteral("torrentDefaultInactiveSeedingTimeMins"), m_torrentDefaultInactiveSeedingTimeMins);
    m_settings.setValue(QStringLiteral("torrentDefaultShareLimitAction"), m_torrentDefaultShareLimitAction);
    m_settings.setValue(QStringLiteral("torrentCustomUserAgent"),      m_torrentCustomUserAgent);
    m_settings.setValue(QStringLiteral("torrentBindInterface"),        m_torrentBindInterface);
    m_settings.setValue(QStringLiteral("torrentBannedPeers"),          m_torrentBannedPeers);
    m_settings.setValue(QStringLiteral("torrentBlockedPeerUserAgents"), m_torrentBlockedPeerUserAgents);
    m_settings.setValue(QStringLiteral("torrentBlockedPeerCountries"), m_torrentBlockedPeerCountries);
    m_settings.setValue(QStringLiteral("torrentAutoBanAbusivePeers"), m_torrentAutoBanAbusivePeers);
    m_settings.setValue(QStringLiteral("torrentAutoBanMediaPlayerPeers"), m_torrentAutoBanMediaPlayerPeers);
    m_settings.setValue(QStringLiteral("torrentEncryptionMode"),          m_torrentEncryptionMode);
    m_settings.setValue(QStringLiteral("torrentHistoricalUploadedBytes"),   m_torrentHistoricalUploadedBytes);
    m_settings.setValue(QStringLiteral("torrentHistoricalDownloadedBytes"), m_torrentHistoricalDownloadedBytes);
    m_settings.setValue(QStringLiteral("proxyType"),                   m_proxyType);
    m_settings.setValue(QStringLiteral("proxyHost"),                   m_proxyHost);
    m_settings.setValue(QStringLiteral("proxyPort"),                   m_proxyPort);
    m_settings.setValue(QStringLiteral("proxyUsername"),               obfuscateCred(m_proxyUsername));
    m_settings.setValue(QStringLiteral("proxyPassword"),               obfuscateCred(m_proxyPassword));
    m_settings.setValue(QStringLiteral("perHostConnectionLimit"),     m_perHostConnectionLimit);
    m_settings.setValue(QStringLiteral("rssEnabled"),               m_rssEnabled);
    m_settings.setValue(QStringLiteral("rssRefreshIntervalMins"),   m_rssRefreshIntervalMins);
    m_settings.setValue(QStringLiteral("rssSameHostDelayMs"),       m_rssSameHostDelayMs);
    m_settings.setValue(QStringLiteral("rssMaxArticlesPerFeed"),    m_rssMaxArticlesPerFeed);
    m_settings.setValue(QStringLiteral("rssAutoDownloadEnabled"),   m_rssAutoDownloadEnabled);
    m_settings.setValue(QStringLiteral("rssSmartFilterRepack"),     m_rssSmartFilterRepack);
    m_settings.setValue(QStringLiteral("rssSmartFiltersJson"),      m_rssSmartFiltersJson);
    m_settings.setValue(QStringLiteral("rssDownloadRulesJson"),     m_rssDownloadRulesJson);
    m_settings.sync();
}

void AppSettings::setMaxConcurrent(int v)         { if (m_maxConcurrent        != v) { m_maxConcurrent        = v; emit maxConcurrentChanged();        save(); } }
void AppSettings::setSegmentsPerDownload(int v)   { if (m_segmentsPerDownload  != v) { m_segmentsPerDownload  = v; emit segmentsPerDownloadChanged();  save(); } }
void AppSettings::setDefaultSavePath(const QString &v) { if (m_defaultSavePath != v) { m_defaultSavePath      = v; emit defaultSavePathChanged();      save(); } }
void AppSettings::setTemporaryDirectory(const QString &v) { if (m_temporaryDirectory != v) { m_temporaryDirectory = v; emit temporaryDirectoryChanged(); save(); } }
void AppSettings::setGlobalSpeedLimitKBps(int v)  { if (m_globalSpeedLimitKBps != v) { m_globalSpeedLimitKBps = v; emit globalSpeedLimitKBpsChanged(); save(); } }
void AppSettings::setMinimizeToTray(bool v)        { if (m_minimizeToTray      != v) { m_minimizeToTray       = v; emit minimizeToTrayChanged();       save(); } }
void AppSettings::setCloseToTray(bool v)           { if (m_closeToTray         != v) { m_closeToTray          = v; emit closeToTrayChanged();          save(); } }
void AppSettings::setMaxRetries(int v)             { if (m_maxRetries          != v) { m_maxRetries           = v; emit maxRetriesChanged();           save(); } }
void AppSettings::setConnectionTimeoutSecs(int v)  { if (m_connectionTimeoutSecs != v) { m_connectionTimeoutSecs = v; emit connectionTimeoutSecsChanged(); save(); } }
void AppSettings::setMonitoredExtensions(const QStringList &v) { if (m_monitoredExtensions != v) { m_monitoredExtensions = v; emit monitoredExtensionsChanged(); save(); } }
void AppSettings::setExcludedSites(const QStringList &v)       { if (m_excludedSites       != v) { m_excludedSites       = v; emit excludedSitesChanged();       save(); } }
void AppSettings::setExcludedAddresses(const QStringList &v)   { if (m_excludedAddresses   != v) { m_excludedAddresses   = v; emit excludedAddressesChanged();   save(); } }
void AppSettings::setShowExceptionsDialog(bool v)              { if (m_showExceptionsDialog != v) { m_showExceptionsDialog = v; emit showExceptionsDialogChanged(); save(); } }
void AppSettings::setShowTips(bool v)                          { if (m_showTips            != v) { m_showTips            = v; emit showTipsChanged();            save(); } }
void AppSettings::setDuplicateAction(int v)                    { if (m_duplicateAction     != v) { m_duplicateAction     = v; emit duplicateActionChanged();     save(); } }
void AppSettings::setStartImmediately(bool v)       { if (m_startImmediately       != v) { m_startImmediately       = v; emit startImmediatelyChanged();       save(); } }
void AppSettings::setSpeedLimiterOnStartup(bool v)  { if (m_speedLimiterOnStartup  != v) { m_speedLimiterOnStartup  = v; emit speedLimiterOnStartupChanged();  save(); } }
void AppSettings::setSavedSpeedLimitKBps(int v)     { if (m_savedSpeedLimitKBps    != v) { m_savedSpeedLimitKBps    = v; emit savedSpeedLimitKBpsChanged();    save(); } }
void AppSettings::setShowDownloadComplete(bool v)   { if (m_showDownloadComplete   != v) { m_showDownloadComplete   = v; emit showDownloadCompleteChanged();   save(); } }
void AppSettings::setShowCompletionNotification(bool v) { if (m_showCompletionNotification != v) { m_showCompletionNotification = v; emit showCompletionNotificationChanged(); save(); } }
void AppSettings::setShowErrorNotification(bool v) { if (m_showErrorNotification != v) { m_showErrorNotification = v; emit showErrorNotificationChanged(); save(); } }
void AppSettings::setShowFinishedCount(bool v)      { if (m_showFinishedCount      != v) { m_showFinishedCount      = v; emit showFinishedCountChanged();      save(); } }
void AppSettings::setSpeedInTrayTooltip(bool v)     { if (m_speedInTrayTooltip     != v) { m_speedInTrayTooltip     = v; emit speedInTrayTooltipChanged();     save(); } }
void AppSettings::setSpeedInTitleBar(bool v)        { if (m_speedInTitleBar        != v) { m_speedInTitleBar        = v; emit speedInTitleBarChanged();        save(); } }
void AppSettings::setSpeedInStatusBar(bool v)       { if (m_speedInStatusBar       != v) { m_speedInStatusBar       = v; emit speedInStatusBarChanged();       save(); } }
void AppSettings::setRatioInStatusBar(bool v)       { if (m_ratioInStatusBar       != v) { m_ratioInStatusBar       = v; emit ratioInStatusBarChanged();       save(); } }
void AppSettings::setStartDownloadWhileFileInfo(bool v) { if (m_startDownloadWhileFileInfo != v) { m_startDownloadWhileFileInfo = v; emit startDownloadWhileFileInfoChanged(); save(); } }
void AppSettings::setShowQueueSelectionOnDownloadLater(bool v) { if (m_showQueueSelectionOnDownloadLater != v) { m_showQueueSelectionOnDownloadLater = v; emit showQueueSelectionOnDownloadLaterChanged(); save(); } }
void AppSettings::setShowQueueSelectionOnBatchDownload(bool v) { if (m_showQueueSelectionOnBatchDownload != v) { m_showQueueSelectionOnBatchDownload = v; emit showQueueSelectionOnBatchDownloadChanged(); save(); } }
void AppSettings::setUseCustomUserAgent(bool v)     { if (m_useCustomUserAgent     != v) { m_useCustomUserAgent     = v; emit useCustomUserAgentChanged();     save(); } }
void AppSettings::setCustomUserAgent(const QString &v) { if (m_customUserAgent != v) { m_customUserAgent = v; emit customUserAgentChanged(); save(); } }
void AppSettings::setDownloadTableColumns(const QString &v) { if (m_downloadTableColumns != v) { m_downloadTableColumns = v; emit downloadTableColumnsChanged(); save(); } }
void AppSettings::setGrabberFilesToExploreAtOnce(int v) { if (m_grabberFilesToExploreAtOnce != v) { m_grabberFilesToExploreAtOnce = v; emit grabberFilesToExploreAtOnceChanged(); save(); } }
void AppSettings::setGrabberFilesToDownloadAtOnce(int v) { if (m_grabberFilesToDownloadAtOnce != v) { m_grabberFilesToDownloadAtOnce = v; emit grabberFilesToDownloadAtOnceChanged(); save(); } }
void AppSettings::setGrabberUseLinkTextAsDescription(bool v) { if (m_grabberUseLinkTextAsDescription != v) { m_grabberUseLinkTextAsDescription = v; emit grabberUseLinkTextAsDescriptionChanged(); save(); } }
void AppSettings::setGrabberUseAdvancedProcessing(bool v) { if (m_grabberUseAdvancedProcessing != v) { m_grabberUseAdvancedProcessing = v; emit grabberUseAdvancedProcessingChanged(); save(); } }
void AppSettings::setGrabberIncludeFiltersJson(const QString &v) { if (m_grabberIncludeFiltersJson != v) { m_grabberIncludeFiltersJson = v; emit grabberIncludeFiltersJsonChanged(); save(); } }
void AppSettings::setGrabberExcludeFiltersJson(const QString &v) { if (m_grabberExcludeFiltersJson != v) { m_grabberExcludeFiltersJson = v; emit grabberExcludeFiltersJsonChanged(); save(); } }
void AppSettings::setSidebarOrder(const QStringList &v) { if (m_sidebarOrder != v) { m_sidebarOrder = v; emit sidebarOrderChanged(); save(); } }
void AppSettings::setTorrentSubcatOrder(const QStringList &v) { if (m_torrentSubcatOrder != v) { m_torrentSubcatOrder = v; emit torrentSubcatOrderChanged(); save(); } }
void AppSettings::setBypassInterceptKey(int v)     { if (m_bypassInterceptKey     != v) { m_bypassInterceptKey     = v; emit bypassInterceptKeyChanged();     save(); } }

void AppSettings::setLaunchOnStartup(bool v) {
    if (m_launchOnStartup != v) {
        m_launchOnStartup = v;
        emit launchOnStartupChanged();
        // Register or unregister with the OS so Stellar starts with the system
        applyStartupRegistration(v);
        save();
    }
}

void AppSettings::setClipboardMonitorEnabled(bool v) {
    if (m_clipboardMonitorEnabled != v) {
        m_clipboardMonitorEnabled = v;
        emit clipboardMonitorEnabledChanged();
        save();
    }
}

void AppSettings::setDoubleClickAction(int v) {
    if (m_doubleClickAction != v) {
        m_doubleClickAction = v;
        emit doubleClickActionChanged();
        save();
    }
}

void AppSettings::setSpeedScheduleEnabled(bool v) {
    if (m_speedScheduleEnabled != v) {
        m_speedScheduleEnabled = v;
        emit speedScheduleEnabledChanged();
        save();
    }
}

void AppSettings::setSpeedScheduleJson(const QString &v) {
    if (m_speedScheduleJson != v) {
        m_speedScheduleJson = v;
        emit speedScheduleJsonChanged();
        save();
    }
}

void AppSettings::setAutoCheckUpdates(bool v) {
    if (m_autoCheckUpdates != v) {
        m_autoCheckUpdates = v;
        emit autoCheckUpdatesChanged();
        save();
    }
}

void AppSettings::setSkippedUpdateVersion(const QString &v) {
    if (m_skippedUpdateVersion != v) {
        m_skippedUpdateVersion = v;
        emit skippedUpdateVersionChanged();
        save();
    }
}

void AppSettings::setLastTryDateStyle(int v) {
    if (m_lastTryDateStyle != v) {
        m_lastTryDateStyle = v;
        emit lastTryDateStyleChanged();
        save();
    }
}

void AppSettings::setLastTryUse24Hour(bool v) {
    if (m_lastTryUse24Hour != v) {
        m_lastTryUse24Hour = v;
        emit lastTryUse24HourChanged();
        save();
    }
}

void AppSettings::setLastTryShowSeconds(bool v) {
    if (m_lastTryShowSeconds != v) {
        m_lastTryShowSeconds = v;
        emit lastTryShowSecondsChanged();
        save();
    }
}

void AppSettings::setMainWindowX(int v) {
    if (m_mainWindowX != v) {
        m_mainWindowX = v;
        emit mainWindowXChanged();
        save();
    }
}

void AppSettings::setMainWindowY(int v) {
    if (m_mainWindowY != v) {
        m_mainWindowY = v;
        emit mainWindowYChanged();
        save();
    }
}

void AppSettings::setMainWindowWidth(int v) {
    if (m_mainWindowWidth != v) {
        m_mainWindowWidth = v;
        emit mainWindowWidthChanged();
        save();
    }
}

void AppSettings::setMainWindowHeight(int v) {
    if (m_mainWindowHeight != v) {
        m_mainWindowHeight = v;
        emit mainWindowHeightChanged();
        save();
    }
}

void AppSettings::setYtdlpCustomBinaryPath(const QString &v) {
    if (m_ytdlpCustomBinaryPath != v) {
        m_ytdlpCustomBinaryPath = v;
        emit ytdlpCustomBinaryPathChanged();
        save();
    }
}

void AppSettings::setYtdlpAutoUpdate(bool v) {
    if (m_ytdlpAutoUpdate != v) {
        m_ytdlpAutoUpdate = v;
        emit ytdlpAutoUpdateChanged();
        save();
    }
}

void AppSettings::setYtdlpJsRuntimePath(const QString &v) {
    if (m_ytdlpJsRuntimePath != v) {
        m_ytdlpJsRuntimePath = v;
        emit ytdlpJsRuntimePathChanged();
        save();
    }
}

void AppSettings::setTorrentEnableDht(bool v)             { if (m_torrentEnableDht != v) { m_torrentEnableDht = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentEnableLsd(bool v)             { if (m_torrentEnableLsd != v) { m_torrentEnableLsd = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentEnableUpnp(bool v)            { if (m_torrentEnableUpnp != v) { m_torrentEnableUpnp = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentEnableNatPmp(bool v)          { if (m_torrentEnableNatPmp != v) { m_torrentEnableNatPmp = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentListenPort(int v)             { if (m_torrentListenPort != v) { m_torrentListenPort = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentConnectionsLimit(int v)              { if (m_torrentConnectionsLimit != v) { m_torrentConnectionsLimit = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentConnectionsLimitPerTorrent(int v)    { if (m_torrentConnectionsLimitPerTorrent != v) { m_torrentConnectionsLimitPerTorrent = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentUploadSlotsLimit(int v)              { if (m_torrentUploadSlotsLimit != v) { m_torrentUploadSlotsLimit = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentUploadSlotsLimitPerTorrent(int v)    { if (m_torrentUploadSlotsLimitPerTorrent != v) { m_torrentUploadSlotsLimitPerTorrent = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentProtocol(int v)                      { if (m_torrentProtocol != v) { m_torrentProtocol = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentDownloadLimitKBps(int v)             { if (m_torrentDownloadLimitKBps != v) { m_torrentDownloadLimitKBps = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentUploadLimitKBps(int v)        { if (m_torrentUploadLimitKBps != v) { m_torrentUploadLimitKBps = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setGlobalUploadLimitKBps(int v)         { if (m_globalUploadLimitKBps != v) { m_globalUploadLimitKBps = v; emit globalUploadLimitKBpsChanged(); save(); } }
void AppSettings::setTorrentDefaultShareRatio(double v)   { if (m_torrentDefaultShareRatio != v) { m_torrentDefaultShareRatio = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentDefaultSeedingTimeMins(int v) { if (m_torrentDefaultSeedingTimeMins != v) { m_torrentDefaultSeedingTimeMins = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentDefaultInactiveSeedingTimeMins(int v) { if (m_torrentDefaultInactiveSeedingTimeMins != v) { m_torrentDefaultInactiveSeedingTimeMins = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentDefaultShareLimitAction(int v) { if (m_torrentDefaultShareLimitAction != v) { m_torrentDefaultShareLimitAction = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentCustomUserAgent(const QString &v) { if (m_torrentCustomUserAgent != v) { m_torrentCustomUserAgent = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentBindInterface(const QString &v) { if (m_torrentBindInterface != v) { m_torrentBindInterface = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentBannedPeers(const QStringList &v) { if (m_torrentBannedPeers != v) { m_torrentBannedPeers = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentBlockedPeerUserAgents(const QString &v) { if (m_torrentBlockedPeerUserAgents != v) { m_torrentBlockedPeerUserAgents = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentBlockedPeerCountries(const QStringList &v) { if (m_torrentBlockedPeerCountries != v) { m_torrentBlockedPeerCountries = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentAutoBanAbusivePeers(bool v) { if (m_torrentAutoBanAbusivePeers != v) { m_torrentAutoBanAbusivePeers = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentAutoBanMediaPlayerPeers(bool v) { if (m_torrentAutoBanMediaPlayerPeers != v) { m_torrentAutoBanMediaPlayerPeers = v; emit torrentSettingsChanged(); save(); } }
void AppSettings::setTorrentEncryptionMode(int v) { if (m_torrentEncryptionMode != v) { m_torrentEncryptionMode = v; emit torrentSettingsChanged(); save(); } }

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

void AppSettings::setPerHostConnectionLimit(int v) { if (m_perHostConnectionLimit != v) { m_perHostConnectionLimit = v; emit perHostConnectionLimitChanged(); save(); } }

void AppSettings::setProxyType(int v)            { if (m_proxyType     != v) { m_proxyType     = v; emit proxyTypeChanged();     save(); } }
void AppSettings::setProxyHost(const QString &v) { if (m_proxyHost     != v) { m_proxyHost     = v; emit proxyHostChanged();     save(); } }
void AppSettings::setProxyPort(int v)            { if (m_proxyPort     != v) { m_proxyPort     = v; emit proxyPortChanged();     save(); } }
void AppSettings::setProxyUsername(const QString &v) { if (m_proxyUsername != v) { m_proxyUsername = v; emit proxyUsernameChanged(); save(); } }
void AppSettings::setProxyPassword(const QString &v) { if (m_proxyPassword != v) { m_proxyPassword = v; emit proxyPasswordChanged(); save(); } }
void AppSettings::setRssEnabled(bool v)              { if (m_rssEnabled != v)              { m_rssEnabled = v;              emit rssEnabledChanged();              save(); } }
void AppSettings::setRssRefreshIntervalMins(int v)   { if (m_rssRefreshIntervalMins != v)  { m_rssRefreshIntervalMins = v;  emit rssRefreshIntervalMinsChanged();  save(); } }
void AppSettings::setRssSameHostDelayMs(int v)       { if (m_rssSameHostDelayMs != v)      { m_rssSameHostDelayMs = v;      emit rssSameHostDelayMsChanged();      save(); } }
void AppSettings::setRssMaxArticlesPerFeed(int v)    { if (m_rssMaxArticlesPerFeed != v)   { m_rssMaxArticlesPerFeed = v;   emit rssMaxArticlesPerFeedChanged();   save(); } }
void AppSettings::setRssAutoDownloadEnabled(bool v)  { if (m_rssAutoDownloadEnabled != v)  { m_rssAutoDownloadEnabled = v;  emit rssAutoDownloadEnabledChanged();  save(); } }
void AppSettings::setRssSmartFilterRepack(bool v)    { if (m_rssSmartFilterRepack != v)    { m_rssSmartFilterRepack = v;    emit rssSmartFilterRepackChanged();    save(); } }
void AppSettings::setRssSmartFiltersJson(const QString &v) { if (m_rssSmartFiltersJson != v) { m_rssSmartFiltersJson = v; emit rssSmartFiltersJsonChanged(); save(); } }
void AppSettings::setRssDownloadRulesJson(const QString &v) { if (m_rssDownloadRulesJson != v) { m_rssDownloadRulesJson = v; emit rssDownloadRulesJsonChanged(); save(); } }

void AppSettings::applyStartupRegistration(bool enable) const {
#ifdef Q_OS_WIN
    // Windows: write/remove the value under the standard Run key.
    // Using NativeFormat gives us direct registry access without .ini indirection.
    QSettings runKey(
        QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"),
        QSettings::NativeFormat);
    if (enable) {
        // Store the path with forward-slash → backslash so the shell finds it.
        // --minimized tells the app to start hidden in the tray on OS login.
        const QString exePath = QCoreApplication::applicationFilePath().replace('/', '\\');
        runKey.setValue(QStringLiteral("Stellar"),
                        QStringLiteral("\"%1\" --minimized").arg(exePath));
    } else {
        runKey.remove(QStringLiteral("Stellar"));
    }
#elif defined(Q_OS_LINUX)
    // Linux/XDG: write a .desktop file in ~/.config/autostart/ (XDG standard).
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
