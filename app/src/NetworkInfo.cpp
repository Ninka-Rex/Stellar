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

    // Step 1: find the active wireless interface name.
    // /proc/net/wireless lists every wireless iface with current stats. Format
    // (after two header lines):
    //   <iface>: status link.    level.   noise.   ...
    // Trailing dots on numeric fields are *part* of the field (a quirk of the
    // format); strip them with a regex that grabs the integer prefix.
    QString iface;
    int signalPct = 0;
    int rssi = 0;
    {
        QFile wireless(QStringLiteral("/proc/net/wireless"));
        if (wireless.open(QIODevice::ReadOnly | QIODevice::Text)) {
            int lineNo = 0;
            while (!wireless.atEnd()) {
                const QString line = QString::fromUtf8(wireless.readLine()).trimmed();
                if (++lineNo <= 2) continue;
                const int colon = line.indexOf(QLatin1Char(':'));
                if (colon <= 0) continue;
                iface = line.left(colon).trimmed();

                static const QRegularExpression numRe(QStringLiteral("-?\\d+"));
                const QString rest = line.mid(colon + 1);
                const QStringList cols = rest.split(QRegularExpression(QStringLiteral("\\s+")),
                                                    Qt::SkipEmptyParts);
                // Columns: status, link quality, signal level (dBm), noise level, ...
                if (cols.size() >= 3) {
                    const auto linkM = numRe.match(cols.value(1));
                    const auto rssiM = numRe.match(cols.value(2));
                    if (linkM.hasMatch()) {
                        // /proc/net/wireless link quality is on a 0–70 scale.
                        const int link = linkM.captured(0).toInt();
                        signalPct = qBound(0, static_cast<int>((link / 70.0) * 100.0), 100);
                    }
                    if (rssiM.hasMatch())
                        rssi = rssiM.captured(0).toInt();
                }
                break;
            }
        }
    }

    // Fallback for systems where /proc/net/wireless is empty/missing: pick the
    // first interface name that looks wireless.
    if (iface.isEmpty()) {
        for (const QNetworkInterface &i : QNetworkInterface::allInterfaces()) {
            if (!i.flags().testFlag(QNetworkInterface::IsUp)
                || !i.flags().testFlag(QNetworkInterface::IsRunning)
                || i.flags().testFlag(QNetworkInterface::IsLoopBack))
                continue;
            if (nameSuggestsWireless(i.name(), i.humanReadableName())) {
                iface = i.name();
                break;
            }
        }
    }
    if (iface.isEmpty())
        return result;

    // Step 2: extract SSID, and if the /proc parse missed signal info, also
    // grab dBm from `iw dev <iface> link`. iw output looks like:
    //   Connected to xx:xx:... (on wlan0)
    //     SSID: MyNetwork
    //     freq: 5180
    //     signal: -45 dBm
    //     ...
    // Falls back to `iwconfig` on legacy systems where iw isn't installed.
    QString ssid;
    auto runProcess = [](const QString &program, const QStringList &args) -> QString {
        QProcess p;
        p.start(program, args);
        if (!p.waitForFinished(800))
            return {};
        return QString::fromUtf8(p.readAllStandardOutput());
    };

    QString out = runProcess(QStringLiteral("iw"), {QStringLiteral("dev"), iface, QStringLiteral("link")});
    if (out.isEmpty()) {
        // Some environments (Flatpak sandbox without --talk-name) block iw;
        // try iwgetid as a lighter alternative for the SSID at minimum.
        ssid = runProcess(QStringLiteral("iwgetid"),
                          {QStringLiteral("-r"), iface}).trimmed();
    } else {
        static const QRegularExpression ssidRe(QStringLiteral("(?m)^\\s*SSID:\\s*(.+)$"));
        static const QRegularExpression sigRe(QStringLiteral("(?m)signal:\\s*(-?\\d+)\\s*dBm"));
        const auto sm = ssidRe.match(out);
        if (sm.hasMatch())
            ssid = sm.captured(1).trimmed();
        if (rssi == 0) {
            const auto rm = sigRe.match(out);
            if (rm.hasMatch()) {
                rssi = rm.captured(1).toInt();
                // Linear conversion matching the Windows wlan_signal_quality
                // mapping: -100 dBm → 0%, -50 dBm or better → 100%.
                if (signalPct == 0)
                    signalPct = qBound(0, 2 * (rssi + 100), 100);
            }
        }
    }

    if (ssid.isEmpty()) {
        // Last-ditch fallback for SSID — iwconfig, present on older distros.
        const QString iwc = runProcess(QStringLiteral("iwconfig"), {iface});
        static const QRegularExpression iwcSsidRe(QStringLiteral("ESSID:\"([^\"]*)\""));
        const auto m = iwcSsidRe.match(iwc);
        if (m.hasMatch())
            ssid = m.captured(1);
    }

    result[QStringLiteral("ssid")]          = ssid;
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
