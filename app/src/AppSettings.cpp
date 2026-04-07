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
      m_settings(QStringLiteral("StellarProject"), QStringLiteral("Stellar"))
{
    m_defaultSavePath = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
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

    emit maxConcurrentChanged();
    emit segmentsPerDownloadChanged();
    emit defaultSavePathChanged();
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
}

void AppSettings::save() {
    m_settings.setValue(QStringLiteral("maxConcurrent"),         m_maxConcurrent);
    m_settings.setValue(QStringLiteral("segmentsPerDownload"),   m_segmentsPerDownload);
    m_settings.setValue(QStringLiteral("defaultSavePath"),       m_defaultSavePath);
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
    m_settings.sync();
}

void AppSettings::setMaxConcurrent(int v)         { if (m_maxConcurrent        != v) { m_maxConcurrent        = v; emit maxConcurrentChanged();        save(); } }
void AppSettings::setSegmentsPerDownload(int v)   { if (m_segmentsPerDownload  != v) { m_segmentsPerDownload  = v; emit segmentsPerDownloadChanged();  save(); } }
void AppSettings::setDefaultSavePath(const QString &v) { if (m_defaultSavePath != v) { m_defaultSavePath      = v; emit defaultSavePathChanged();      save(); } }
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
