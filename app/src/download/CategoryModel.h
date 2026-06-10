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
#include <QList>
#include <QStandardPaths>

struct Category {
    QString id;
    QString label;
    QString iconPath;       // QRC icon path for sidebar display
    QStringList extensions; // file extensions (without dot), empty = match all
    QStringList sitePatterns; // wildcard patterns for URL host matching
    QString defaultSavePath;
    bool builtIn{false};    // built-in categories cannot be deleted
};

class CategoryModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        LabelRole,
        IconRole,
        SavePathRole,
        ExtensionsRole,
        SitePatternsRole,
        BuiltInRole
    };

    explicit CategoryModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE QString categoryForFilename(const QString &filename) const;
    Q_INVOKABLE QString categoryForUrl(const QUrl &url, const QString &filename) const;
    Q_INVOKABLE QString savePathForCategory(const QString &categoryId) const;

    // Category CRUD — called from AppController
    Q_INVOKABLE int categoryCount() const { return m_categories.size(); }
    Q_INVOKABLE QString addCategory(const QString &label);
    Q_INVOKABLE bool removeCategory(const QString &categoryId);
    Q_INVOKABLE void updateCategory(const QString &categoryId,
                                    const QString &label,
                                    const QStringList &extensions,
                                    const QStringList &sitePatterns,
                                    const QString &savePath);
    Q_INVOKABLE QVariantMap categoryData(int row) const;
    Q_INVOKABLE void moveCategory(int fromRow, int toRow);

signals:
    void categoriesChanged();

private:
    QList<Category> m_categories;
    QString m_downloadsBase;

    void initDefaults();
    void loadFromDisk();
    void saveToDisk() const;
    QString categoriesFilePath() const;
    bool matchesSitePattern(const QString &host, const QString &pattern) const;
};
