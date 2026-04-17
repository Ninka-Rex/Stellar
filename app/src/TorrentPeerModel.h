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
#include <QHash>
#include <QVariantMap>
#include <QVector>

class TorrentPeerModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool hasLocalLocation READ hasLocalLocation NOTIFY localLocationChanged)
    Q_PROPERTY(double localLatitude READ localLatitude NOTIFY localLocationChanged)
    Q_PROPERTY(double localLongitude READ localLongitude NOTIFY localLocationChanged)
    Q_PROPERTY(QString localIp READ localIp NOTIFY localLocationChanged)
    Q_PROPERTY(int localPort READ localPort NOTIFY localLocationChanged)
    Q_PROPERTY(QString localCountryCode READ localCountryCode NOTIFY localLocationChanged)
    Q_PROPERTY(QString localRegionName READ localRegionName NOTIFY localLocationChanged)
    Q_PROPERTY(QString localCityName READ localCityName NOTIFY localLocationChanged)
    Q_PROPERTY(QString localClientName READ localClientName NOTIFY localLocationChanged)
public:
    enum Roles {
        EndpointRole = Qt::UserRole + 1,
        PortRole,
        ClientRole,
        ProgressRole,
        DownSpeedRole,
        UpSpeedRole,
        DownloadedRole,
        UploadedRole,
        SeedRole,
        CountryCodeRole,
        CountryFlagRole,
        RegionCodeRole,
        RegionNameRole,
        CityNameRole,
        LatitudeRole,
        LongitudeRole,
        RttRole,
        SourceRole,
        FlagsRole
    };

    struct Entry {
        QString endpoint;
        int port{0};
        QString client;
        double progress{0.0};
        int downSpeed{0};
        int upSpeed{0};
        qint64 downloaded{0};
        qint64 uploaded{0};
        bool isSeed{false};
        QString countryCode;
        QString countryFlag;
        QString regionCode;
        QString regionName;
        QString cityName;
        double latitude{0.0};
        double longitude{0.0};
        int rtt{0};
        QString source;
        QString flags; // space-separated: IN OUT TRK DHT PEX LSD UTP ENC SNB UPO OPT HPX
    };

    explicit TorrentPeerModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool hasLocalLocation() const { return m_hasLocalLocation; }
    double localLatitude() const { return m_localLatitude; }
    double localLongitude() const { return m_localLongitude; }
    QString localIp() const { return m_localIp; }
    int localPort() const { return m_localPort; }
    QString localCountryCode() const { return m_localCountryCode; }
    QString localRegionName() const { return m_localRegionName; }
    QString localCityName() const { return m_localCityName; }
    QString localClientName() const { return m_localClientName; }

    void setEntries(const QVector<Entry> &entries);
    void setLocalLocation(bool hasLocation, double latitude, double longitude);
    void setLocalInfo(const QString &ip, int port, const QString &countryCode,
                      const QString &regionName, const QString &cityName,
                      const QString &clientName);
    Q_INVOKABLE void sortBy(const QString &key, bool ascending);
    Q_INVOKABLE QString peerKeyAt(int row) const;
    Q_INVOKABLE int indexOfPeerKey(const QString &key) const;
    Q_INVOKABLE bool removePeerByKey(const QString &key);
    Q_INVOKABLE bool removePeer(const QString &endpoint, int port);
    Q_INVOKABLE QVariantMap breakdownByClient() const;
    Q_INVOKABLE QVariantMap breakdownByCountry() const;
    Q_INVOKABLE void setLiveUpdatesEnabled(bool enabled);
    Q_INVOKABLE bool liveUpdatesEnabled() const { return m_liveUpdatesEnabled; }
    Q_INVOKABLE void setStructuralUpdatesDeferred(bool deferred);
    Q_INVOKABLE bool structuralUpdatesDeferred() const { return m_structuralUpdatesDeferred; }

signals:
    void localLocationChanged();

private:
    QVector<Entry> m_entries;
    QString m_sortKey{QStringLiteral("endpoint")};
    bool m_sortAscending{true};
    QHash<QString, int> m_missingPeerStreaks;
    QVector<Entry> m_pendingEntries;
    bool m_liveUpdatesEnabled{true};
    bool m_structuralUpdatesDeferred{false};
    bool m_hasLocalLocation{false};
    double m_localLatitude{0.0};
    double m_localLongitude{0.0};
    QString m_localIp;
    int m_localPort{0};
    QString m_localCountryCode;
    QString m_localRegionName;
    QString m_localCityName;
    QString m_localClientName;
};
