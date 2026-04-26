#include "NetworkInfo.h"

#include <QNetworkInterface>
#include <QString>

#ifdef Q_OS_WIN
#  include <winsock2.h>
#  include <windows.h>
#  include <wlanapi.h>
#  pragma comment(lib, "wlanapi.lib")
#endif

#ifdef Q_OS_LINUX
#  include <QFile>
#  include <QProcess>
#  include <QRegularExpression>
#endif

namespace {

// Heuristic: classify an interface by name. QNetworkInterface in Qt 6 doesn't
// expose a direct "is wireless" flag cross-platform, so we look at the
// hardware name. Common wireless prefixes:
//   Linux:   wl* (modern udev), wlan*, ath*, ra*, wifi*
//   Windows: includes "Wi-Fi", "Wireless", "WLAN" in the human-readable name
bool nameSuggestsWireless(const QString &name, const QString &humanName) {
    static const QStringList kWirelessNames = {
        QStringLiteral("wl"),    QStringLiteral("wlan"),
        QStringLiteral("ath"),   QStringLiteral("ra"),
        QStringLiteral("wifi"),  QStringLiteral("wlp")
    };
    const QString lname = name.toLower();
    for (const auto &p : kWirelessNames) {
        if (lname.startsWith(p))
            return true;
    }
    const QString hl = humanName.toLower();
    return hl.contains(QStringLiteral("wi-fi"))
        || hl.contains(QStringLiteral("wifi"))
        || hl.contains(QStringLiteral("wireless"))
        || hl.contains(QStringLiteral("wlan"))
        || hl.contains(QStringLiteral("802.11"));
}

bool nameSuggestsVirtual(const QString &name, const QString &humanName) {
    const QString hl = humanName.toLower();
    if (hl.contains(QStringLiteral("virtual"))
        || hl.contains(QStringLiteral("vmware"))
        || hl.contains(QStringLiteral("hyper-v"))
        || hl.contains(QStringLiteral("vethernet"))
        || hl.contains(QStringLiteral("loopback"))
        || hl.contains(QStringLiteral("bluetooth"))
        || hl.contains(QStringLiteral("tap"))
        || hl.contains(QStringLiteral("tun")))
        return true;
    const QString ln = name.toLower();
    return ln.startsWith(QStringLiteral("vmnet"))
        || ln.startsWith(QStringLiteral("docker"))
        || ln.startsWith(QStringLiteral("br-"));
}

} // namespace

int NetworkInfo::activeInterfaceType() const {
    // Walk all interfaces, prefer the one with a default IPv4 address that
    // isn't link-local. We rank wireless lower priority than ethernet only
    // when both are simultaneously up, which is uncommon for end users.
    InterfaceType best = None;
    for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces()) {
        const auto flags = iface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp)
            || !flags.testFlag(QNetworkInterface::IsRunning)
            || flags.testFlag(QNetworkInterface::IsLoopBack))
            continue;
        if (nameSuggestsVirtual(iface.name(), iface.humanReadableName()))
            continue;

        bool hasRoutableAddr = false;
        for (const QNetworkAddressEntry &a : iface.addressEntries()) {
            const QHostAddress &ip = a.ip();
            if (ip.isNull() || ip.isLoopback() || ip.isLinkLocal())
                continue;
            hasRoutableAddr = true;
            break;
        }
        if (!hasRoutableAddr)
            continue;

        InterfaceType t = nameSuggestsWireless(iface.name(), iface.humanReadableName())
                              ? Wifi : Ethernet;
        // Ethernet wins over WiFi if both are present (typical desktop setup).
        if (t == Ethernet) return Ethernet;
        if (best == None) best = t;
    }
    return best;
}

#ifdef Q_OS_WIN
QVariantMap NetworkInfo::queryActiveWifi() const {
    QVariantMap result;
    result[QStringLiteral("available")] = false;

    HANDLE handle = nullptr;
    DWORD negotiatedVersion = 0;
    if (WlanOpenHandle(2, nullptr, &negotiatedVersion, &handle) != ERROR_SUCCESS)
        return result;

    PWLAN_INTERFACE_INFO_LIST list = nullptr;
    if (WlanEnumInterfaces(handle, nullptr, &list) != ERROR_SUCCESS || !list) {
        WlanCloseHandle(handle, nullptr);
        return result;
    }

    for (DWORD i = 0; i < list->dwNumberOfItems; ++i) {
        const WLAN_INTERFACE_INFO &iface = list->InterfaceInfo[i];
        if (iface.isState != wlan_interface_state_connected)
            continue;

        PWLAN_CONNECTION_ATTRIBUTES attrs = nullptr;
        DWORD attrSize = 0;
        WLAN_OPCODE_VALUE_TYPE opcode;
        if (WlanQueryInterface(handle, &iface.InterfaceGuid,
                               wlan_intf_opcode_current_connection,
                               nullptr, &attrSize,
                               reinterpret_cast<PVOID *>(&attrs), &opcode)
            != ERROR_SUCCESS || !attrs) {
            continue;
        }

        const auto &assoc = attrs->wlanAssociationAttributes;
        const QString ssid = QString::fromLocal8Bit(
            reinterpret_cast<const char *>(assoc.dot11Ssid.ucSSID),
            static_cast<int>(assoc.dot11Ssid.uSSIDLength));
        const int signalPct = static_cast<int>(assoc.wlanSignalQuality); // 0–100
        // Microsoft documents wlanSignalQuality as a linear scale of dBm:
        // 0 = -100 dBm or worse, 100 = -50 dBm or better.
        const int rssi = -100 + (signalPct / 2);

        result[QStringLiteral("ssid")]          = ssid;
        result[QStringLiteral("signalPercent")] = signalPct;
        result[QStringLiteral("rssiDbm")]       = rssi;
        result[QStringLiteral("available")]     = true;

        WlanFreeMemory(attrs);
        break;
    }

    WlanFreeMemory(list);
    WlanCloseHandle(handle, nullptr);
    return result;
}
#elif defined(Q_OS_LINUX)
QVariantMap NetworkInfo::queryActiveWifi() const {
    QVariantMap result;
    result[QStringLiteral("available")] = false;

    // Find the first wireless interface by walking /proc/net/wireless.
    // Format (after two header lines):
    //   <iface>: status link level noise ...
    QFile wireless(QStringLiteral("/proc/net/wireless"));
    if (!wireless.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    QString iface;
    int signalPct = 0;
    int rssi = 0;
    int lineNo = 0;
    while (!wireless.atEnd()) {
        const QString line = QString::fromUtf8(wireless.readLine()).trimmed();
        if (++lineNo <= 2) continue; // skip headers

        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0) continue;
        iface = line.left(colon).trimmed();
        const QString rest = line.mid(colon + 1).trimmed();
        // Columns: status, link quality, signal level (dBm), noise level
        const QStringList cols = rest.split(QRegularExpression(QStringLiteral("\\s+")),
                                            Qt::SkipEmptyParts);
        if (cols.size() >= 3) {
            const double link = cols.value(1).remove(QLatin1Char('.')).toDouble();
            // /proc/net/wireless reports link quality on a 0–70 scale.
            signalPct = qBound(0, static_cast<int>((link / 70.0) * 100.0), 100);
            rssi = cols.value(2).remove(QLatin1Char('.')).toInt();
        }
        break;
    }
    wireless.close();

    if (iface.isEmpty())
        return result;

    // SSID via `iw dev <iface> link`. iw is the modern userspace tool that
    // ships with wireless-tools on virtually every desktop distro.
    QProcess p;
    p.start(QStringLiteral("iw"), {QStringLiteral("dev"), iface, QStringLiteral("link")});
    if (p.waitForFinished(800)) {
        const QString out = QString::fromUtf8(p.readAllStandardOutput());
        const QRegularExpression ssidRe(QStringLiteral("SSID:\\s*(.+)"));
        const auto m = ssidRe.match(out);
        if (m.hasMatch())
            result[QStringLiteral("ssid")] = m.captured(1).trimmed();
    }

    result[QStringLiteral("signalPercent")] = signalPct;
    result[QStringLiteral("rssiDbm")]       = rssi;
    result[QStringLiteral("available")]     = true;
    return result;
}
#else
QVariantMap NetworkInfo::queryActiveWifi() const {
    QVariantMap result;
    result[QStringLiteral("available")] = false;
    return result;
}
#endif
