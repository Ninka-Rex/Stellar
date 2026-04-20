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

#include "TorrentSearchManager.h"

#include "AppVersion.h"
#include "TorrentSearchPluginModel.h"
#include "TorrentSearchResultModel.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include "StellarPaths.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcessEnvironment>
#include <QSettings>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>

namespace {
QString userPluginDir() {
    return StellarPaths::searchPluginsDir();
}

QString parseTag(const QString &content, const QString &name) {
    const QRegularExpression re(QStringLiteral("^#\\s*%1:\\s*(.+)$")
                                .arg(QRegularExpression::escape(name)),
                                QRegularExpression::MultilineOption | QRegularExpression::CaseInsensitiveOption);
    const auto match = re.match(content);
    return match.hasMatch() ? match.captured(1).trimmed() : QString();
}

QString parseStaticString(const QString &content, const QString &name) {
    const QRegularExpression re(QStringLiteral("\\b%1\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
                                .arg(QRegularExpression::escape(name)));
    const auto match = re.match(content);
    return match.hasMatch() ? match.captured(1).trimmed() : QString();
}

TorrentSearchResultModel::Entry entryFromJsonObject(const QJsonObject &obj) {
    TorrentSearchResultModel::Entry entry;
    entry.name = obj.value(QStringLiteral("name")).toString();
    entry.sizeText = obj.value(QStringLiteral("size")).toString();
    entry.sizeBytes = static_cast<qint64>(obj.value(QStringLiteral("sizeBytes")).toDouble(-1));
    entry.seeders = obj.value(QStringLiteral("seeders")).toInt(-1);
    entry.leechers = obj.value(QStringLiteral("leechers")).toInt(-1);
    entry.engine = obj.value(QStringLiteral("engine")).toString();
    entry.publishedOn = obj.value(QStringLiteral("publishedOn")).toString();
    entry.pluginFile = obj.value(QStringLiteral("pluginFile")).toString();
    entry.downloadLink = obj.value(QStringLiteral("downloadLink")).toString();
    entry.magnetLink = obj.value(QStringLiteral("magnetLink")).toString();
    entry.descriptionUrl = obj.value(QStringLiteral("descriptionUrl")).toString();
    return entry;
}
}

TorrentSearchManager::TorrentSearchManager(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent),
      m_nam(nam),
      m_pluginModel(new TorrentSearchPluginModel(this)),
      m_resultModel(new TorrentSearchResultModel(this))
{
    ensureBundledPluginsInstalled();
    refreshPlugins();
    refreshRuntimeState();
}

QString TorrentSearchManager::pluginDirectory() const {
    return userPluginDir();
}

QString TorrentSearchManager::disabledPluginsKey() const {
    return QStringLiteral("torrentSearchDisabledPlugins");
}

QString TorrentSearchManager::runnerScriptPath() {
    const QString outPath = StellarPaths::searchRunnerFile();
    QFile outFile(outPath);
    QFile resourceFile(QStringLiteral(":/qt/qml/com/stellar/app/app/scripts/torrent_search_runner.py"));
    if (!resourceFile.exists())
        resourceFile.setFileName(QStringLiteral(":/torrent_search_runner.py"));
    if (!resourceFile.open(QIODevice::ReadOnly))
        return outPath;
    const QByteArray payload = resourceFile.readAll();
    if (!outFile.exists() || (outFile.open(QIODevice::ReadOnly) && outFile.readAll() != payload)) {
        if (outFile.isOpen())
            outFile.close();
        if (outFile.open(QIODevice::WriteOnly | QIODevice::Truncate))
            outFile.write(payload);
    }
    return outPath;
}

QString TorrentSearchManager::bundledPluginResourcePath(const QString &fileName) const {
    const QString qmlPath = QStringLiteral(":/qt/qml/com/stellar/app/app/search_plugins/%1").arg(fileName);
    if (QFileInfo::exists(qmlPath))
        return qmlPath;
    const QString rootPath = QStringLiteral(":/search_plugins/%1").arg(fileName);
    return QFileInfo::exists(rootPath) ? rootPath : QString();
}

void TorrentSearchManager::ensureBundledPluginsInstalled() {
    static const QStringList bundledPlugins = {
        QStringLiteral("bitsearch.py"),
        QStringLiteral("limetorrents.py"),
        QStringLiteral("piratebay.py"),
        QStringLiteral("linuxtracker.py"),
        QStringLiteral("torrentproject.py"),
        QStringLiteral("torrentscsv.py")
    };

    // Only (re)install bundled plugins when the app version changes — i.e. on
    // first run or after an upgrade/reinstall. This ensures fresh installs get
    // all plugins while respecting the user's decision to delete individual
    // files between upgrades (deleted files are not reinstated mid-version).
    QSettings settings(StellarPaths::settingsFile(), QSettings::IniFormat);
    const QString currentVersion = QStringLiteral(STELLAR_VERSION);
    const QString installedVersion = settings.value(QStringLiteral("searchPluginsInstalledVersion")).toString();
    if (installedVersion == currentVersion)
        return;

    QDir().mkpath(pluginDirectory());
    for (const QString &fileName : bundledPlugins) {
        const QString resourcePath = bundledPluginResourcePath(fileName);
        if (resourcePath.isEmpty())
            continue;
        const QString targetPath = QDir(pluginDirectory()).filePath(fileName);
        if (QFileInfo::exists(targetPath))
            continue;

        QFile source(resourcePath);
        if (!source.open(QIODevice::ReadOnly))
            continue;
        QFile target(targetPath);
        if (!target.open(QIODevice::WriteOnly | QIODevice::Truncate))
            continue;
        target.write(source.readAll());
    }

    settings.setValue(QStringLiteral("searchPluginsInstalledVersion"), currentVersion);
}

QString TorrentSearchManager::detectPython() const {
    const QStringList path = QProcessEnvironment::systemEnvironment().value(QStringLiteral("PATH"))
                                 .split(QDir::listSeparator(), Qt::SkipEmptyParts);
    QString candidate = QStandardPaths::findExecutable(QStringLiteral("python3"), path);
    if (!candidate.isEmpty() && canRunPython(candidate))
        return candidate;
    candidate = QStandardPaths::findExecutable(QStringLiteral("python"), path);
    if (!candidate.isEmpty() && canRunPython(candidate))
        return candidate;
#if defined(Q_OS_WIN)
    candidate = QStandardPaths::findExecutable(QStringLiteral("py"), path);
    if (!candidate.isEmpty() && canRunPython(candidate))
        return candidate;

    const QString localAppData = QProcessEnvironment::systemEnvironment().value(QStringLiteral("LOCALAPPDATA"));
    const QStringList windowsCandidates = {
        QDir(localAppData).filePath(QStringLiteral("Programs/Python/Python313/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Programs/Python/Python312/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Programs/Python/Python311/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Programs/Python/Python310/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Programs/Python/Python39/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Microsoft/WindowsApps/python.exe")),
        QDir(localAppData).filePath(QStringLiteral("Microsoft/WindowsApps/py.exe"))
    };
    for (const QString &pathCandidate : windowsCandidates) {
        if (QFileInfo::exists(pathCandidate) && canRunPython(pathCandidate))
            return pathCandidate;
    }
#endif
    return QString();
}

bool TorrentSearchManager::canRunPython(const QString &program) const {
    if (program.isEmpty())
        return false;

    QProcess probe;
    QStringList args;
#if defined(Q_OS_WIN)
    if (QFileInfo(program).baseName().compare(QStringLiteral("py"), Qt::CaseInsensitive) == 0)
        args << QStringLiteral("-3");
#endif
    args << QStringLiteral("--version");
    probe.setProgram(program);
    probe.setArguments(args);
    probe.setProcessChannelMode(QProcess::MergedChannels);
    probe.start();
    if (!probe.waitForStarted(1500)) {
        probe.kill();
        return false;
    }
    if (!probe.waitForFinished(3000)) {
        probe.kill();
        return false;
    }
    return probe.exitStatus() == QProcess::NormalExit && probe.exitCode() == 0;
}

void TorrentSearchManager::refreshRuntimeState() {
    const QString python = detectPython();
    const bool changed = m_pythonExecutable != python;
    m_pythonExecutable = python;
    if (changed)
        emit stateChanged();
}

QVector<TorrentSearchManager::PluginInfo> TorrentSearchManager::scanPlugins() const {
    QSettings settings(StellarPaths::settingsFile(), QSettings::IniFormat);
    const QStringList disabledList = settings.value(disabledPluginsKey()).toStringList();
    const QSet<QString> disabled(disabledList.begin(), disabledList.end());
    QDir dir(pluginDirectory());
    const QFileInfoList files = dir.entryInfoList({ QStringLiteral("*.py") }, QDir::Files, QDir::Name);
    QVector<PluginInfo> plugins;
    plugins.reserve(files.size());
    for (const QFileInfo &info : files) {
        QFile file(info.absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QString content = QString::fromUtf8(file.readAll());
        PluginInfo plugin;
        plugin.fileName = info.fileName();
        plugin.version = parseTag(content, QStringLiteral("VERSION"));
        plugin.displayName = parseStaticString(content, QStringLiteral("name"));
        plugin.url = parseStaticString(content, QStringLiteral("url"));
        plugin.enabled = !disabled.contains(plugin.fileName);
        plugins.push_back(plugin);
    }
    return plugins;
}

void TorrentSearchManager::refreshPlugins() {
    const QVector<PluginInfo> plugins = scanPlugins();
    QVector<TorrentSearchPluginModel::Entry> entries;
    entries.reserve(plugins.size());
    for (const PluginInfo &plugin : plugins) {
        TorrentSearchPluginModel::Entry entry;
        entry.fileName = plugin.fileName;
        entry.displayName = plugin.displayName;
        entry.version = plugin.version;
        entry.url = plugin.url;
        entry.enabled = plugin.enabled;
        entries.push_back(entry);
    }
    m_pluginModel->setEntries(entries);
}

void TorrentSearchManager::setStatusText(const QString &text) {
    if (m_statusText == text)
        return;
    m_statusText = text;
    emit stateChanged();
}

void TorrentSearchManager::setSearchInProgress(bool inProgress) {
    if (m_searchInProgress == inProgress)
        return;
    m_searchInProgress = inProgress;
    emit stateChanged();
}

void TorrentSearchManager::search(const QString &query) {
    refreshRuntimeState();
    const QString trimmed = query.trimmed();
    if (trimmed.isEmpty()) {
        setStatusText(QStringLiteral("Enter a search query."));
        return;
    }
    refreshPlugins();
    QStringList enabledPlugins;
    for (int row = 0; row < m_pluginModel->rowCount(); ++row) {
        const QVariantMap plugin = m_pluginModel->pluginData(row);
        if (plugin.value(QStringLiteral("enabled")).toBool())
            enabledPlugins << plugin.value(QStringLiteral("fileName")).toString();
    }
    if (enabledPlugins.isEmpty()) {
        setStatusText(QStringLiteral("Enable at least one search plugin first."));
        return;
    }
    if (m_pythonExecutable.isEmpty()) {
        setStatusText(QStringLiteral("Python was not found. Install Python or add it to PATH, then reopen Search Engine."));
        return;
    }
    if (m_searchProcess) {
        m_searchProcess->kill();
        m_searchProcess->deleteLater();
    }
    auto *proc = new QProcess(this);
    m_searchProcess = proc;
    m_searchStdoutBuffer.clear();
    m_resultModel->clear();
    proc->setProgram(m_pythonExecutable);
    QStringList args;
#if defined(Q_OS_WIN)
    if (QFileInfo(m_pythonExecutable).baseName().compare(QStringLiteral("py"), Qt::CaseInsensitive) == 0)
        args << QStringLiteral("-3");
#endif
    args << runnerScriptPath() << pluginDirectory() << trimmed;
    args << enabledPlugins;
    proc->setArguments(args);
    proc->setProcessChannelMode(QProcess::SeparateChannels);
    setSearchInProgress(true);
    setStatusText(QStringLiteral("Searching %1 plugin(s)...").arg(enabledPlugins.size()));
    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
        m_searchStdoutBuffer += QString::fromUtf8(proc->readAllStandardOutput());
        while (true) {
            const int newline = m_searchStdoutBuffer.indexOf(QLatin1Char('\n'));
            if (newline < 0)
                break;
            const QString line = m_searchStdoutBuffer.left(newline).trimmed();
            m_searchStdoutBuffer.remove(0, newline + 1);
            if (line.isEmpty())
                continue;

            const QJsonDocument doc = QJsonDocument::fromJson(line.toUtf8());
            if (!doc.isObject())
                continue;
            const QJsonObject obj = doc.object();
            const QString type = obj.value(QStringLiteral("type")).toString();
            if (type == QStringLiteral("result")) {
                const TorrentSearchResultModel::Entry entry = entryFromJsonObject(obj.value(QStringLiteral("payload")).toObject());
                if (!entry.name.isEmpty())
                    m_resultModel->appendEntry(entry);
            } else if (type == QStringLiteral("status")) {
                const QString message = obj.value(QStringLiteral("message")).toString();
                if (!message.isEmpty())
                    setStatusText(message);
            }
        }
    });
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            [this, proc](int exitCode, QProcess::ExitStatus) {
        if (proc->bytesAvailable() > 0)
            m_searchStdoutBuffer += QString::fromUtf8(proc->readAllStandardOutput());

        QString message = QString::fromUtf8(proc->readAllStandardError()).trimmed();
        const QStringList lines = m_searchStdoutBuffer.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &rawLine : lines) {
            const QString line = rawLine.trimmed();
            const QJsonDocument doc = QJsonDocument::fromJson(line.toUtf8());
            if (!doc.isObject())
                continue;
            const QJsonObject obj = doc.object();
            const QString type = obj.value(QStringLiteral("type")).toString();
            if (type == QStringLiteral("result")) {
                const TorrentSearchResultModel::Entry entry = entryFromJsonObject(obj.value(QStringLiteral("payload")).toObject());
                if (!entry.name.isEmpty())
                    m_resultModel->appendEntry(entry);
            } else if (type == QStringLiteral("summary")) {
                message = obj.value(QStringLiteral("message")).toString();
            } else if (type == QStringLiteral("status") && message.isEmpty()) {
                message = obj.value(QStringLiteral("message")).toString();
            }
        }
        m_searchStdoutBuffer.clear();
        setSearchInProgress(false);
        setStatusText(!message.isEmpty() ? message
                                         : QStringLiteral("Found %1 result(s).").arg(m_resultModel->rowCount()));
        proc->deleteLater();
        if (m_searchProcess == proc)
            m_searchProcess = nullptr;
    });
    proc->start();
}

void TorrentSearchManager::clearResults() {
    m_resultModel->setEntries({});
    setStatusText(QString());
}

QVariantMap TorrentSearchManager::pluginData(int row) const {
    return m_pluginModel->pluginData(row);
}

QVariantMap TorrentSearchManager::resultData(int row) const {
    return m_resultModel->resultData(row);
}

QString TorrentSearchManager::resolveResultLink(int row, bool preferMagnet) {
    const QVariantMap rowData = resultData(row);
    const QString magnetLink = rowData.value(QStringLiteral("magnetLink")).toString().trimmed();
    const QString downloadLink = rowData.value(QStringLiteral("downloadLink")).toString().trimmed();
    const QString pluginFile = rowData.value(QStringLiteral("pluginFile")).toString().trimmed();

    if (!magnetLink.isEmpty() && magnetLink.startsWith(QStringLiteral("magnet:"), Qt::CaseInsensitive))
        return magnetLink;
    if (pluginFile.isEmpty() && !preferMagnet && !downloadLink.isEmpty())
        return downloadLink;
    if (m_pythonExecutable.isEmpty() || pluginFile.isEmpty() || downloadLink.isEmpty())
        return preferMagnet ? magnetLink : downloadLink;

    QProcess proc;
    proc.setProgram(m_pythonExecutable);
    QStringList args;
#if defined(Q_OS_WIN)
    if (QFileInfo(m_pythonExecutable).baseName().compare(QStringLiteral("py"), Qt::CaseInsensitive) == 0)
        args << QStringLiteral("-3");
#endif
    args << runnerScriptPath() << QStringLiteral("--resolve") << pluginDirectory() << pluginFile << downloadLink;
    proc.setArguments(args);
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start();
    if (!proc.waitForStarted(2000))
        return preferMagnet ? magnetLink : downloadLink;
    if (!proc.waitForFinished(15000))
        return preferMagnet ? magnetLink : downloadLink;

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const QStringList lines = output.split(QRegularExpression(QStringLiteral("[\\r\\n]+")), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QString trimmed = line.trimmed();
        if (trimmed.startsWith(QStringLiteral("magnet:"), Qt::CaseInsensitive)) {
            const QRegularExpression magnetRe(QStringLiteral(R"(magnet:\?[^\s]+)"),
                                              QRegularExpression::CaseInsensitiveOption);
            const QRegularExpressionMatch match = magnetRe.match(trimmed);
            if (match.hasMatch())
                return match.captured(0);
            return trimmed.section(QLatin1Char(' '), 0, 0).trimmed();
        }
        if (trimmed.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)
                || trimmed.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive))
            return trimmed.section(QLatin1Char(' '), 0, 0).trimmed();
    }
    return preferMagnet ? magnetLink : downloadLink;
}

void TorrentSearchManager::setPluginEnabled(const QString &fileName, bool enabled) {
    QSettings settings(StellarPaths::settingsFile(), QSettings::IniFormat);
    QStringList disabled = settings.value(disabledPluginsKey()).toStringList();
    disabled.removeAll(fileName);
    if (!enabled)
        disabled.append(fileName);
    disabled.removeDuplicates();
    settings.setValue(disabledPluginsKey(), disabled);
    settings.sync();
    refreshPlugins();
}

bool TorrentSearchManager::togglePluginEnabled(int row) {
    if (row < 0 || row >= m_pluginModel->rowCount())
        return false;
    const QVariantMap plugin = m_pluginModel->pluginData(row);
    const QString fileName = plugin.value(QStringLiteral("fileName")).toString().trimmed();
    const bool enabled = plugin.value(QStringLiteral("enabled")).toBool();
    if (fileName.isEmpty())
        return false;
    const bool ok = m_pluginModel->setEnabled(row, !enabled);
    setPluginEnabled(fileName, !enabled);
    return ok;
}

bool TorrentSearchManager::uninstallPlugin(const QString &fileName) {
    const QString trimmed = fileName.trimmed();
    if (trimmed.isEmpty())
        return false;

    // Accept only plain plugin filenames (no path segments), and only .py plugins.
    const QFileInfo nameInfo(trimmed);
    if (nameInfo.fileName() != trimmed
        || nameInfo.suffix().compare(QStringLiteral("py"), Qt::CaseInsensitive) != 0) {
        return false;
    }

    static const QRegularExpression kSafePluginName(
        QStringLiteral("^[A-Za-z0-9_.-]+\\.py$"),
        QRegularExpression::CaseInsensitiveOption);
    if (!kSafePluginName.match(trimmed).hasMatch())
        return false;

    const QDir pluginDir(pluginDirectory());
    // QDir::cleanPath always uses forward slashes, so use '/' as the separator
    // when building the prefix — not QDir::separator() which is '\' on Windows.
    const QString pluginRoot = QDir::cleanPath(pluginDir.absolutePath());
    const QString candidatePath = QDir::cleanPath(pluginDir.absoluteFilePath(trimmed));
    const Qt::CaseSensitivity cs =
#if defined(Q_OS_WIN)
        Qt::CaseInsensitive;
#else
        Qt::CaseSensitive;
#endif
    const QString rootPrefix = pluginRoot + QLatin1Char('/');
    if (candidatePath.compare(pluginRoot, cs) != 0
        && !candidatePath.startsWith(rootPrefix, cs)) {
        return false;
    }

    const QString path = candidatePath;
    const bool ok = QFile::remove(path);
    refreshPlugins();
    return ok;
}

bool TorrentSearchManager::installPluginFromFile(const QString &filePath) {
    QFileInfo info(filePath);
    if (!info.exists() || info.suffix().compare(QStringLiteral("py"), Qt::CaseInsensitive) != 0) {
        emit pluginInstallFinished(false, QStringLiteral("Pick a Python plugin file."));
        return false;
    }
    QDir().mkpath(pluginDirectory());
    const QString target = QDir(pluginDirectory()).filePath(info.fileName());
    QFile::remove(target);
    const bool ok = QFile::copy(filePath, target);
    refreshPlugins();
    emit pluginInstallFinished(ok, ok ? QStringLiteral("Installed %1.").arg(info.fileName())
                                      : QStringLiteral("Failed to install %1.").arg(info.fileName()));
    return ok;
}

void TorrentSearchManager::installPluginFromUrl(const QString &url) {
    const QUrl targetUrl = QUrl::fromUserInput(url.trimmed());
    if (!targetUrl.isValid() || targetUrl.isEmpty()) {
        emit pluginInstallFinished(false, QStringLiteral("Enter a valid plugin URL."));
        return;
    }
    if (!m_nam) {
        emit pluginInstallFinished(false, QStringLiteral("Network manager is unavailable."));
        return;
    }
    QNetworkReply *reply = m_nam->get(QNetworkRequest(targetUrl));
    connect(reply, &QNetworkReply::finished, this, [this, reply, targetUrl]() {
        const QByteArray payload = reply->readAll();
        const bool ok = reply->error() == QNetworkReply::NoError;
        reply->deleteLater();
        if (!ok) {
            emit pluginInstallFinished(false, QStringLiteral("Failed to download plugin."));
            return;
        }
        QString fileName = QFileInfo(targetUrl.path()).fileName();
        if (!fileName.endsWith(QStringLiteral(".py"), Qt::CaseInsensitive))
            fileName += QStringLiteral(".py");
        QDir().mkpath(pluginDirectory());
        QFile file(QDir(pluginDirectory()).filePath(fileName));
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            emit pluginInstallFinished(false, QStringLiteral("Failed to write plugin file."));
            return;
        }
        file.write(payload);
        file.close();
        refreshPlugins();
        emit pluginInstallFinished(true, QStringLiteral("Installed %1.").arg(fileName));
    });
}
