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

#include <QMap>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QString>
#include <QVariantMap>

#include "TorrentSearchPluginModel.h"
#include "TorrentSearchResultModel.h"

class QNetworkAccessManager;
class QNetworkReply;

class TorrentSearchManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(TorrentSearchPluginModel *pluginModel READ pluginModel CONSTANT)
    Q_PROPERTY(TorrentSearchResultModel *resultModel READ resultModel CONSTANT)
    Q_PROPERTY(bool searchInProgress READ searchInProgress NOTIFY stateChanged)
    Q_PROPERTY(bool pythonAvailable READ pythonAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(QString pluginDirectory READ pluginDirectory CONSTANT)
public:
    explicit TorrentSearchManager(QNetworkAccessManager *nam, QObject *parent = nullptr);

    TorrentSearchPluginModel *pluginModel() const { return m_pluginModel; }
    TorrentSearchResultModel *resultModel() const { return m_resultModel; }
    bool searchInProgress() const { return m_searchInProgress; }
    bool pythonAvailable() const { return !m_pythonExecutable.isEmpty(); }
    QString statusText() const { return m_statusText; }
    QString pluginDirectory() const;

    Q_INVOKABLE void refreshPlugins();
    Q_INVOKABLE void refreshRuntimeState();
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void clearResults();
    Q_INVOKABLE QVariantMap pluginData(int row) const;
    Q_INVOKABLE QVariantMap resultData(int row) const;
    Q_INVOKABLE QString resolveResultLink(int row, bool preferMagnet = false);
    Q_INVOKABLE bool togglePluginEnabled(int row);
    Q_INVOKABLE void setPluginEnabled(const QString &fileName, bool enabled);
    Q_INVOKABLE bool uninstallPlugin(const QString &fileName);
    Q_INVOKABLE bool installPluginFromFile(const QString &filePath);
    Q_INVOKABLE void installPluginFromUrl(const QString &url);

signals:
    void stateChanged();
    void pluginInstallFinished(bool ok, const QString &message);

private:
    struct PluginInfo {
        QString fileName;
        QString displayName;
        QString version;
        QString url;
        bool enabled{true};
        bool quarantined{false};
    };

    QString disabledPluginsKey() const;
    QString approvedPluginsKey() const;
    // Returns hex SHA-256 of the file at path, or empty on error.
    static QString hashPluginFile(const QString &path);
    // Load filename->sha256 approved map from settings.
    QMap<QString, QString> loadApprovedPlugins() const;
    // Approve a plugin by recording its current hash in settings.
    void approvePlugin(const QString &fileName, const QString &sha256);

    QString runnerScriptPath();
    void ensureBundledPluginsInstalled();
    QString bundledPluginResourcePath(const QString &fileName) const;
    QString detectPython() const;
    bool canRunPython(const QString &program) const;
    QVector<PluginInfo> scanPlugins() const;
    void setStatusText(const QString &text);
    void setSearchInProgress(bool inProgress);

    QNetworkAccessManager *m_nam{nullptr};
    TorrentSearchPluginModel *m_pluginModel{nullptr};
    TorrentSearchResultModel *m_resultModel{nullptr};
    QPointer<QProcess> m_searchProcess;
    bool m_searchInProgress{false};
    QString m_statusText;
    QString m_pythonExecutable;
    QString m_searchStdoutBuffer;
};
