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
#include <QVariantList>
#include <QString>

struct GrabberResult {
    bool checked{true};
    QString url;
    QString filename;
    QString sourcePage;
    qint64 sizeBytes{-1};
};

class GrabberResultModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Role {
        CheckedRole = Qt::UserRole + 1,
        UrlRole,
        FilenameRole,
        SourcePageRole,
        SizeBytesRole,
        SizeTextRole
    };

    explicit GrabberResultModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role) override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;

    Q_INVOKABLE void setResults(const QVariantList &results);
    Q_INVOKABLE void appendResult(const QVariantMap &result);
    Q_INVOKABLE void updateResultSize(const QString &url, qint64 sizeBytes);
    Q_INVOKABLE void setChecked(int row, bool checked);
    Q_INVOKABLE void setAllChecked(bool checked);
    Q_INVOKABLE int checkedCount() const;
    Q_INVOKABLE QVariantList allResults() const;
    Q_INVOKABLE QVariantList checkedResults() const;
    Q_INVOKABLE QVariantMap resultData(int row) const;
    void sortBy(const QString &column, Qt::SortOrder order);

private:
    QList<GrabberResult> m_results;

    static QString sizeText(qint64 sizeBytes);
};
