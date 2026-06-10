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

#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonObject>
#include <QVariantMap>

struct GrabberProject {
    QString id;
    QString name;
    QString startUrl;
    QString statusText;
    QDateTime lastRunAt;
    int resultCount{0};
    QJsonObject config;
};

class GrabberProjectModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        NameRole,
        StartUrlRole,
        StatusTextRole,
        LastRunAtRole,
        ResultCountRole
    };

    explicit GrabberProjectModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE QVariantMap projectData(int row) const;
    Q_INVOKABLE QVariantMap projectDataById(const QString &id) const;
    QList<GrabberProject> projects() const { return m_projects; }
    Q_INVOKABLE QString upsertProject(const QVariantMap &projectMap);
    Q_INVOKABLE bool removeProject(const QString &id);
    Q_INVOKABLE void moveProject(int fromRow, int toRow);
    Q_INVOKABLE void updateProjectRunState(const QString &id,
                                           const QString &statusText,
                                           int resultCount,
                                           const QDateTime &lastRunAt = QDateTime::currentDateTime());

private:
    QList<GrabberProject> m_projects;

    QString projectsFilePath() const;
    void loadFromDisk();
    void saveToDisk() const;
    static GrabberProject fromJson(const QJsonObject &obj);
    static QJsonObject toJson(const GrabberProject &project);
    static QVariantMap toVariantMap(const GrabberProject &project);
    int indexOfProject(const QString &id) const;
};
