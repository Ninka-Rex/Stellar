#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

// NetworkInfo — lightweight helper for status-bar network indicator.
//
// Detects the active network interface type (WiFi vs Ethernet) and, on demand,
// fetches WiFi metadata (SSID, signal strength %, RSSI dBm). The expensive
// platform-specific WiFi calls are gated behind queryActiveWifi() which
// callers invoke only on hover so the status-bar refresh stays cheap.
class NetworkInfo : public QObject {
    Q_OBJECT
public:
    enum InterfaceType {
        None     = 0,
        Wifi     = 1,
        Ethernet = 2,
        Other    = 3,
    };
    Q_ENUM(InterfaceType)

    explicit NetworkInfo(QObject *parent = nullptr) : QObject(parent) {}

    // Cheap: walks QNetworkInterface list to find the first up, non-loopback,
    // non-virtual interface and classifies it.
    Q_INVOKABLE int activeInterfaceType() const;

    // Expensive: opens a platform-specific WiFi handle. Returns:
    //   { ssid: string, signalPercent: int (0–100), rssiDbm: int, available: bool }
    // available=false if no WiFi adapter is present, the call failed, or the
    // platform isn't supported.
    Q_INVOKABLE QVariantMap queryActiveWifi() const;
};
