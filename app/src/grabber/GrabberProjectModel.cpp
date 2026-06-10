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

#include "GrabberProjectModel.h"
#include "StellarPaths.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUuid>

GrabberProjectModel::GrabberProjectModel(QObject *parent)
    : QAbstractListModel(parent)
{
    loadFromDisk();
}

int GrabberProjectModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_projects.size();
}

QVariant GrabberProjectModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_projects.size())
        return {};

    const GrabberProject &project = m_projects.at(index.row());
    switch (role) {
    case IdRole: return project.id;
    case NameRole: return project.name;
    case StartUrlRole: return project.startUrl;
    case StatusTextRole: return project.statusText;
    case LastRunAtRole: return project.lastRunAt;
    case ResultCountRole: return project.resultCount;
    case Qt::DisplayRole: return project.name;
    default: return {};
    }
}

QHash<int, QByteArray> GrabberProjectModel::roleNames() const
{
    return {
        { IdRole, "projectId" },
        { NameRole, "projectName" },
        { StartUrlRole, "projectStartUrl" },
        { StatusTextRole, "projectStatusText" },
        { LastRunAtRole, "projectLastRunAt" },
        { ResultCountRole, "projectResultCount" }
    };
}

QVariantMap GrabberProjectModel::projectData(int row) const
{
    if (row < 0 || row >= m_projects.size())
        return {};
    return toVariantMap(m_projects.at(row));
}

QVariantMap GrabberProjectModel::projectDataById(const QString &id) const
{
    const int idx = indexOfProject(id);
    return idx >= 0 ? toVariantMap(m_projects.at(idx)) : QVariantMap{};
}

QString GrabberProjectModel::upsertProject(const QVariantMap &projectMap)
{
    GrabberProject project;
    project.id = projectMap.value(QStringLiteral("id")).toString().trimmed();
    if (project.id.isEmpty())
        project.id = QStringLiteral("grabber_") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(12);

    project.name = projectMap.value(QStringLiteral("name")).toString().trimmed();
    if (project.name.isEmpty())
        project.name = QStringLiteral("Grabber Project");
    project.startUrl = projectMap.value(QStringLiteral("startUrl")).toString().trimmed();
    project.statusText = projectMap.value(QStringLiteral("statusText")).toString();
    project.resultCount = projectMap.value(QStringLiteral("resultCount")).toInt();

    const QVariant lastRunVariant = projectMap.value(QStringLiteral("lastRunAt"));
    if (lastRunVariant.canConvert<QDateTime>())
        project.lastRunAt = lastRunVariant.toDateTime();
    else
        project.lastRunAt = QDateTime::fromString(lastRunVariant.toString(), Qt::ISODate);

    project.config = QJsonObject::fromVariantMap(projectMap);
    project.config[QStringLiteral("id")] = project.id;
    project.config[QStringLiteral("name")] = project.name;
    project.config[QStringLiteral("startUrl")] = project.startUrl;
    project.config[QStringLiteral("statusText")] = project.statusText;
    project.config[QStringLiteral("resultCount")] = project.resultCount;
    if (project.lastRunAt.isValid())
        project.config[QStringLiteral("lastRunAt")] = project.lastRunAt.toString(Qt::ISODate);

    const int idx = indexOfProject(project.id);
    if (idx >= 0) {
        m_projects[idx] = project;
        emit dataChanged(index(idx), index(idx));
    } else {
        const int row = m_projects.size();
        beginInsertRows({}, row, row);
        m_projects.append(project);
        endInsertRows();
    }

    saveToDisk();
    return project.id;
}

bool GrabberProjectModel::removeProject(const QString &id)
{
    const int idx = indexOfProject(id);
    if (idx < 0)
        return false;

    beginRemoveRows({}, idx, idx);
    m_projects.removeAt(idx);
    endRemoveRows();
    saveToDisk();
    return true;
}

void GrabberProjectModel::moveProject(int fromRow, int toRow)
{
    if (fromRow < 0 || fromRow >= m_projects.size())
        return;
    if (toRow < 0)
        return;
    if (toRow >= m_projects.size())
        toRow = m_projects.size() - 1;
    if (fromRow == toRow)
        return;

    const int destinationRow = (fromRow < toRow) ? (toRow + 1) : toRow;
    if (!beginMoveRows(QModelIndex(), fromRow, fromRow, QModelIndex(), destinationRow))
        return;
    m_projects.move(fromRow, toRow);
    endMoveRows();
    saveToDisk();
}

void GrabberProjectModel::updateProjectRunState(const QString &id,
                                                const QString &statusText,
                                                int resultCount,
                                                const QDateTime &lastRunAt)
{
    const int idx = indexOfProject(id);
    if (idx < 0)
        return;

    GrabberProject &project = m_projects[idx];
    project.statusText = statusText;
    project.resultCount = resultCount;
    project.lastRunAt = lastRunAt;
    project.config[QStringLiteral("statusText")] = statusText;
    project.config[QStringLiteral("resultCount")] = resultCount;
    if (lastRunAt.isValid())
        project.config[QStringLiteral("lastRunAt")] = lastRunAt.toString(Qt::ISODate);

    emit dataChanged(index(idx), index(idx));
    saveToDisk();
}

QString GrabberProjectModel::projectsFilePath() const
{
    return StellarPaths::grabberProjectsFile();
}

void GrabberProjectModel::loadFromDisk()
{
    QFile file(projectsFilePath());
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isArray())
        return;

    const QJsonArray arr = doc.array();
    beginResetModel();
    m_projects.clear();
    for (const QJsonValue &value : arr) {
        if (value.isObject())
            m_projects.append(fromJson(value.toObject()));
    }
    endResetModel();
}

void GrabberProjectModel::saveToDisk() const
{
    QJsonArray arr;
    for (const GrabberProject &project : m_projects)
        arr.append(toJson(project));

    QFile file(projectsFilePath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}

GrabberProject GrabberProjectModel::fromJson(const QJsonObject &obj)
{
    GrabberProject project;
    project.id = obj.value(QStringLiteral("id")).toString();
    project.name = obj.value(QStringLiteral("name")).toString();
    project.startUrl = obj.value(QStringLiteral("startUrl")).toString();
    project.statusText = obj.value(QStringLiteral("statusText")).toString();
    project.resultCount = obj.value(QStringLiteral("resultCount")).toInt();
    project.lastRunAt = QDateTime::fromString(obj.value(QStringLiteral("lastRunAt")).toString(), Qt::ISODate);
    project.config = obj;
    return project;
}

QJsonObject GrabberProjectModel::toJson(const GrabberProject &project)
{
    QJsonObject obj = project.config;
    obj[QStringLiteral("id")] = project.id;
    obj[QStringLiteral("name")] = project.name;
    obj[QStringLiteral("startUrl")] = project.startUrl;
    obj[QStringLiteral("statusText")] = project.statusText;
    obj[QStringLiteral("resultCount")] = project.resultCount;
    if (project.lastRunAt.isValid())
        obj[QStringLiteral("lastRunAt")] = project.lastRunAt.toString(Qt::ISODate);
    return obj;
}

QVariantMap GrabberProjectModel::toVariantMap(const GrabberProject &project)
{
    QVariantMap map = project.config.toVariantMap();
    map[QStringLiteral("id")] = project.id;
    map[QStringLiteral("name")] = project.name;
    map[QStringLiteral("startUrl")] = project.startUrl;
    map[QStringLiteral("statusText")] = project.statusText;
    map[QStringLiteral("resultCount")] = project.resultCount;
    map[QStringLiteral("lastRunAt")] = project.lastRunAt;
    return map;
}

int GrabberProjectModel::indexOfProject(const QString &id) const
{
    for (int i = 0; i < m_projects.size(); ++i) {
        if (m_projects.at(i).id == id)
            return i;
    }
    return -1;
}
