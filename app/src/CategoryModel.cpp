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

#include "CategoryModel.h"
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QStandardPaths>
#include <QUuid>
#include <QRegularExpression>

CategoryModel::CategoryModel(QObject *parent) : QAbstractListModel(parent) {
    m_downloadsBase = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    initDefaults();
    loadFromDisk();
}

void CategoryModel::initDefaults() {
    auto sub = [this](const QString &name) {
        return m_downloadsBase + QDir::separator() + name;
    };

    m_categories = {
        { QStringLiteral("all"),        QStringLiteral("All Downloads"),
          QStringLiteral("icons/categories/all_downloads.png"), {},  {}, m_downloadsBase, true },
        { QStringLiteral("video"),     QStringLiteral("Video"),
          QStringLiteral("icons/categories/video.png"),
          {"mp4","mkv","avi","mov","wmv","flv","webm","m4v","3gp","mpeg","mpg","ogv","rmvb","rm","qt"},
          {}, sub("Video"), true },
        { QStringLiteral("music"),      QStringLiteral("Music"),
          QStringLiteral("icons/categories/note.png"),
          {"mp3","flac","wav","aac","ogg","m4a","wma","aif","ra","opus"},
          {}, sub("Music"), true },
        { QStringLiteral("documents"),  QStringLiteral("Documents"),
          QStringLiteral("icons/categories/documents.png"),
          {"pdf","doc","docx","xls","xlsx","ppt","pptx","odt","txt","epub","azw3","pps"},
          {}, sub("Documents"), true },
        { QStringLiteral("compressed"), QStringLiteral("Compressed"),
          QStringLiteral("icons/categories/compressed.png"),
          {"zip","rar","7z","tar","gz","bz2","xz","zst","ace","sitx","sit","sea","lzh","z","r00","r01","unitypackage"},
          {}, sub("Compressed"), true },
        { QStringLiteral("programs"),   QStringLiteral("Programs"),
          QStringLiteral("icons/categories/programs.png"),
          {"exe","msi","msu","deb","rpm","appimage","dmg","pkg","apk"},
          {}, sub("Programs"), true },
    };
}

// ── Persistence ──────────────────────────────────────────────────────────────

QString CategoryModel::categoriesFilePath() const {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QDir::separator() + QStringLiteral("categories.json");
}

void CategoryModel::loadFromDisk() {
    QFile file(categoriesFilePath());
    if (!file.exists()) return;
    if (!file.open(QIODevice::ReadOnly)) return;

    const QJsonArray arr = QJsonDocument::fromJson(file.readAll()).array();
    file.close();

    // Rebuild m_categories in the order stored on disk, preserving built-in defaults
    // for anything not saved, and appending any user categories at their saved positions.
    QList<Category> ordered;
    ordered.reserve(arr.size());

    for (const QJsonValue &val : arr) {
        const QJsonObject obj = val.toObject();
        const QString id = obj[QStringLiteral("id")].toString();
        if (id.isEmpty()) continue;

        // Find in defaults
        int defaultIdx = -1;
        for (int i = 0; i < m_categories.size(); ++i) {
            if (m_categories[i].id == id) { defaultIdx = i; break; }
        }

        if (defaultIdx >= 0) {
            // Take the built-in entry and apply any saved field overrides
            Category cat = m_categories[defaultIdx];
            if (obj.contains(QStringLiteral("label")))
                cat.label = obj[QStringLiteral("label")].toString();
            if (obj.contains(QStringLiteral("extensions"))) {
                QStringList exts;
                for (const auto &e : obj[QStringLiteral("extensions")].toArray()) exts << e.toString();
                cat.extensions = exts;
            }
            if (obj.contains(QStringLiteral("sitePatterns"))) {
                QStringList sites;
                for (const auto &s : obj[QStringLiteral("sitePatterns")].toArray()) sites << s.toString();
                cat.sitePatterns = sites;
            }
            if (obj.contains(QStringLiteral("savePath")))
                cat.defaultSavePath = obj[QStringLiteral("savePath")].toString();
            ordered.append(cat);
            m_categories.removeAt(defaultIdx); // remove so we know what's left
        } else {
            // User-created category
            Category cat;
            cat.id = id;
            cat.label = obj[QStringLiteral("label")].toString();
            cat.iconPath = QStringLiteral("icons/folder.png");
            cat.builtIn = false;
            cat.defaultSavePath = obj[QStringLiteral("savePath")].toString();
            for (const auto &e : obj[QStringLiteral("extensions")].toArray()) cat.extensions << e.toString();
            for (const auto &s : obj[QStringLiteral("sitePatterns")].toArray()) cat.sitePatterns << s.toString();
            ordered.append(cat);
        }
    }

    // Append any built-in categories not present in the saved file (new defaults added in updates)
    for (const auto &cat : m_categories)
        ordered.append(cat);

    m_categories = ordered;
}

void CategoryModel::saveToDisk() const {
    QJsonArray arr;
    for (const auto &cat : m_categories) {
        // Save all categories (built-in overrides + user categories)
        QJsonObject obj;
        obj[QStringLiteral("id")] = cat.id;
        obj[QStringLiteral("label")] = cat.label;
        obj[QStringLiteral("builtIn")] = cat.builtIn;
        obj[QStringLiteral("savePath")] = cat.defaultSavePath;

        QJsonArray exts;
        for (const auto &e : cat.extensions) exts.append(e);
        obj[QStringLiteral("extensions")] = exts;

        QJsonArray sites;
        for (const auto &s : cat.sitePatterns) sites.append(s);
        obj[QStringLiteral("sitePatterns")] = sites;

        arr.append(obj);
    }

    QFile file(categoriesFilePath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    }
}

// ── Model interface ──────────────────────────────────────────────────────────

int CategoryModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_categories.size();
}

QVariant CategoryModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_categories.size()) return {};
    const auto &cat = m_categories.at(index.row());
    switch (role) {
    case IdRole:           return cat.id;
    case LabelRole:        return cat.label;
    case IconRole:         return cat.iconPath;
    case SavePathRole:     return cat.defaultSavePath;
    case ExtensionsRole:   return cat.extensions;
    case SitePatternsRole: return cat.sitePatterns;
    case BuiltInRole:      return cat.builtIn;
    case Qt::DisplayRole:  return cat.label;
    }
    return {};
}

QHash<int, QByteArray> CategoryModel::roleNames() const {
    return {
        { IdRole,           "categoryId"           },
        { LabelRole,        "categoryLabel"        },
        { IconRole,         "categoryIcon"         },
        { SavePathRole,     "categorySavePath"     },
        { ExtensionsRole,   "categoryExtensions"   },
        { SitePatternsRole, "categorySitePatterns" },
        { BuiltInRole,      "categoryBuiltIn"      },
    };
}

// ── Category matching ────────────────────────────────────────────────────────

bool CategoryModel::matchesSitePattern(const QString &host, const QString &pattern) const {
    // Convert wildcard pattern to regex: * → .*, escape everything else
    QString regex = QRegularExpression::escape(pattern);
    regex.replace(QStringLiteral("\\*"), QStringLiteral(".*"));
    QRegularExpression re(QStringLiteral("^") + regex + QStringLiteral("$"),
                          QRegularExpression::CaseInsensitiveOption);
    return re.match(host).hasMatch();
}

QString CategoryModel::categoryForFilename(const QString &filename) const {
    const QString ext = QFileInfo(filename).suffix().toLower();
    for (int i = 1; i < m_categories.size(); ++i) {
        const auto &cat = m_categories[i];
        if (!cat.extensions.isEmpty() && cat.extensions.contains(ext))
            return cat.id;
    }
    return QStringLiteral("all");
}

QString CategoryModel::categoryForUrl(const QUrl &url, const QString &filename) const {
    const QString host = url.host().toLower();
    const QString ext = QFileInfo(filename).suffix().toLower();

    // First pass: check site pattern matches (more specific)
    for (int i = 1; i < m_categories.size(); ++i) {
        const auto &cat = m_categories[i];
        if (cat.sitePatterns.isEmpty()) continue;
        for (const auto &pattern : cat.sitePatterns) {
            if (matchesSitePattern(host, pattern)) {
                // Site matches — if category also has extensions, require extension match
                if (cat.extensions.isEmpty() || cat.extensions.contains(ext))
                    return cat.id;
            }
        }
    }

    // Second pass: extension-only matching
    for (int i = 1; i < m_categories.size(); ++i) {
        const auto &cat = m_categories[i];
        if (!cat.extensions.isEmpty() && cat.extensions.contains(ext))
            return cat.id;
    }

    return QStringLiteral("all");
}

QString CategoryModel::savePathForCategory(const QString &categoryId) const {
    for (const auto &cat : m_categories) {
        if (cat.id == categoryId)
            return cat.defaultSavePath;
    }
    return m_downloadsBase;
}

// ── CRUD ─────────────────────────────────────────────────────────────────────

QString CategoryModel::addCategory(const QString &label) {
    Category cat;
    cat.id = QStringLiteral("user_") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    cat.label = label.isEmpty() ? QStringLiteral("New Category") : label;
    cat.iconPath = QStringLiteral("icons/folder.png");
    cat.defaultSavePath = m_downloadsBase;
    cat.builtIn = false;

    const int row = m_categories.size();
    beginInsertRows({}, row, row);
    m_categories.append(cat);
    endInsertRows();
    saveToDisk();
    emit categoriesChanged();
    return cat.id;
}

bool CategoryModel::removeCategory(const QString &categoryId) {
    for (int i = 0; i < m_categories.size(); ++i) {
        if (m_categories[i].id == categoryId) {
            if (m_categories[i].builtIn) return false;
            beginRemoveRows({}, i, i);
            m_categories.removeAt(i);
            endRemoveRows();
            saveToDisk();
            emit categoriesChanged();
            return true;
        }
    }
    return false;
}

void CategoryModel::updateCategory(const QString &categoryId,
                                   const QString &label,
                                   const QStringList &extensions,
                                   const QStringList &sitePatterns,
                                   const QString &savePath) {
    for (int i = 0; i < m_categories.size(); ++i) {
        if (m_categories[i].id == categoryId) {
            m_categories[i].label = label;
            m_categories[i].extensions = extensions;
            m_categories[i].sitePatterns = sitePatterns;
            m_categories[i].defaultSavePath = savePath;
            emit dataChanged(index(i), index(i));
            saveToDisk();
            emit categoriesChanged();
            return;
        }
    }
}

void CategoryModel::moveCategory(int fromRow, int toRow) {
    // toRow == m_categories.size() means "drop after last item" — clamp to last valid index.
    if (toRow >= m_categories.size()) toRow = m_categories.size() - 1;
    // Bounds and no-op checks
    if (fromRow < 0 || fromRow >= m_categories.size()) return;
    if (toRow   < 0) return;
    if (fromRow == toRow) return;
    // Protect the "all" category at index 0 — it is always first
    if (fromRow == 0 || toRow == 0) return;

    // QAbstractListModel::beginMoveRows destination is the row BEFORE which the item is inserted,
    // so when moving forward we use toRow+1 as the destination.
    beginResetModel();
    m_categories.move(fromRow, toRow);
    endResetModel();

    saveToDisk();
    emit categoriesChanged();
}

QVariantMap CategoryModel::categoryData(int row) const {
    if (row < 0 || row >= m_categories.size()) return {};
    const auto &cat = m_categories.at(row);
    return {
        {QStringLiteral("id"),           cat.id},
        {QStringLiteral("label"),        cat.label},
        {QStringLiteral("iconPath"),     cat.iconPath},
        {QStringLiteral("extensions"),   QVariant::fromValue(cat.extensions)},
        {QStringLiteral("sitePatterns"), QVariant::fromValue(cat.sitePatterns)},
        {QStringLiteral("savePath"),     cat.defaultSavePath},
        {QStringLiteral("builtIn"),      cat.builtIn},
    };
}
