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
    // Batch-insert multiple results in one beginInsertRows/endInsertRows pair.
    // Prefer this over repeated appendResult calls to avoid O(n²) notification cost.
    void appendResults(const QList<GrabberResult> &results);
    Q_INVOKABLE void updateResultSize(const QString &url, qint64 sizeBytes);
    Q_INVOKABLE void setChecked(int row, bool checked);
    Q_INVOKABLE void setAllChecked(bool checked);
    // O(1) — maintained by an incremental counter, never iterates m_results.
    Q_INVOKABLE int checkedCount() const;
    Q_INVOKABLE QVariantList allResults() const;
    Q_INVOKABLE QVariantList checkedResults() const;
    Q_INVOKABLE QVariantMap resultData(int row) const;
    void sortBy(const QString &column, Qt::SortOrder order);

    // Active sort column/order — kept so that appendResults and updateResultSize
    // can maintain sort order without a full model reset (uses layoutChanged instead).
    QString sortColumn() const { return m_sortColumn; }

private:
    QList<GrabberResult> m_results;
    int m_checkedCount{0}; // maintained incrementally — never recomputed from scratch
    QString m_sortColumn;
    Qt::SortOrder m_sortOrder{Qt::AscendingOrder};

    // Re-sorts m_results in-place using layoutAboutToBeChanged/layoutChanged so the
    // ListView does not reset its scroll position.  Only called for live updates
    // (new rows inserted, size metadata arrived); user-triggered sortBy() still uses
    // beginResetModel so the view scrolls back to the top as expected.
    void applySortLayout();

    static QString sizeText(qint64 sizeBytes);
};
