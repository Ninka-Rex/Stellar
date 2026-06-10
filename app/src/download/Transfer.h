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
#include <QObject>
#include <QString>

// Common abstract base for queued, pausable file-download engines managed by
// DownloadQueue: HTTP/HTTPS via SegmentedTransfer and FTP/FTPS via FtpTransfer.
//
// DownloadQueue stores workers as Transfer* and drives every download through
// this interface, so both engines share the same concurrency cap, pause/resume,
// relocate, and speed-limit semantics. Engines that don't need an HTTP-only knob
// (e.g. the custom User-Agent) inherit the no-op default.
class Transfer : public QObject {
    Q_OBJECT

public:
    // Shared progress/timing constants — single source of truth for both engines'
    // sliding-window speed, stall detection, retry backoff, and meta-save cadence.
    static constexpr int kTickIntervalMs        = 250;     // onProgressTick cadence
    static constexpr int kSpeedWindowTicks      = 120;     // 30 s ETA window (120 × 250 ms)
    static constexpr int kDisplayWindowTicks    = 8;       // 2 s display window
    static constexpr int kMetaSaveIntervalTicks = 20;      // save meta every 5 s
    static constexpr int kStallTimeoutMs        = 30'000;  // no bytes in this window → retry
    static constexpr int kMaxSegmentRetries     = 4;       // per-segment retry cap

    explicit Transfer(QObject *parent = nullptr) : QObject(parent) {}
    ~Transfer() override = default;

    // Lifecycle — implemented by each concrete engine.
    virtual void start()  = 0;
    virtual void pause()  = 0;
    virtual void resume() = 0;
    virtual void abort()  = 0;
    virtual bool relocateOutput(const QString &newSavePath,
                                const QString &newFilename) = 0;

    virtual void setSpeedLimitKBps(int kbps)               = 0;
    virtual void setTemporaryDirectory(const QString &path) = 0;
    virtual void setMaxConnectionsPerHost(int v)           = 0;

    // HTTP-only knobs. Base provides no-op defaults so DownloadQueue's broadcast
    // loops can call them uniformly on every Transfer*; non-HTTP engines ignore them.
    virtual void setCustomUserAgentEnabled(bool /*enabled*/) {}
    virtual void setCustomUserAgent(const QString & /*userAgent*/) {}

signals:
    void started();
    void progressChanged(qint64 done, qint64 total, qint64 speedBps);
    void finished();
    void failed(const QString &reason);
    // Emitted when the downloaded file appears to be a small HTML error/expiry
    // page instead of the expected content (HTTP engine only, but declared here
    // so DownloadQueue can wire it through a Transfer* uniformly).
    void fileDeletedWarning();
};
