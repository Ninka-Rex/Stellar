#include "MediaMetadata.h"

#include <QtEndian>
#include <climits>
#include <cstring>

// All readers in this file operate on untrusted, possibly-truncated server data.
// Helpers below never read past `data.size()`; every multi-byte read is guarded.

namespace {

// ── bounds-checked endian readers ────────────────────────────────────────────
static inline bool inBounds(const QByteArray &d, int off, int len) {
    return off >= 0 && len >= 0 && off <= d.size() - len;
}
static inline quint16 rdU16LE(const QByteArray &d, int off) {
    const quint8 *p = (const quint8 *)d.constData() + off;
    return (quint16)(p[0] | (p[1] << 8));
}
static inline quint32 rdU32LE(const QByteArray &d, int off) {
    const quint8 *p = (const quint8 *)d.constData() + off;
    return (quint32)p[0] | ((quint32)p[1] << 8) | ((quint32)p[2] << 16) | ((quint32)p[3] << 24);
}
static inline quint64 rdU64LE(const QByteArray &d, int off) {
    return (quint64)rdU32LE(d, off) | ((quint64)rdU32LE(d, off + 4) << 32);
}
static inline quint16 rdU16BE(const QByteArray &d, int off) {
    const quint8 *p = (const quint8 *)d.constData() + off;
    return (quint16)((p[0] << 8) | p[1]);
}
static inline quint32 rdU32BE(const QByteArray &d, int off) {
    const quint8 *p = (const quint8 *)d.constData() + off;
    return ((quint32)p[0] << 24) | ((quint32)p[1] << 16) | ((quint32)p[2] << 8) | (quint32)p[3];
}

// Sanitize a server-supplied text field (EXIF make/model, etc.) for display:
// printable ASCII only, no control chars/newlines, length-capped.
static QString sanitizeText(const QByteArray &raw, int maxLen = 64) {
    QString out;
    for (char c : raw) {
        if (out.size() >= maxLen) break;
        quint8 u = (quint8)c;
        if (u == 0) break;                 // C-string terminator
        if (u >= 0x20 && u < 0x7F) out.append(QChar(u));
    }
    return out.trimmed();
}

// ── helpers for content-type/ext dispatch ────────────────────────────────────
static inline bool ctHas(const QString &ct, const char *needle) {
    return ct.contains(QLatin1String(needle));
}

// ════════════════════════════════════════════════════════════════════════════
//  AUDIO
// ════════════════════════════════════════════════════════════════════════════

// ── MP3 ──────────────────────────────────────────────────────────────────────
struct Mp3Info { int bitrate{0}; int sampleRate{0}; int channels{0}; };
static Mp3Info parseMp3Frame(const QByteArray &data) {
    int offset = 0;
    if (data.size() >= 10 && data.startsWith("ID3")) {
        int sz = ((quint8)data[6] << 21) | ((quint8)data[7] << 14)
               | ((quint8)data[8] << 7)  |  (quint8)data[9];
        offset = 10 + sz;
        if (data.size() > offset + 3 && data[offset] == 0x00)
            offset++; // unsync padding
    }
    static const int bitrateTableV1L3[] = {0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
    static const int bitrateTableV2L3[] = {0, 8,16,24,32,40,48,56, 64, 80,96, 112,128,144,160,0};
    static const int srTable[]          = {44100,48000,32000,0};
    static const int srTableV2[]        = {22050,24000,16000,0};
    static const int srTableV25[]       = {11025,12000, 8000,0};

    for (int i = offset; i + 3 < data.size(); ++i) {
        quint8 b0 = (quint8)data[i], b1 = (quint8)data[i+1];
        if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) continue;
        quint8 b2 = (quint8)data[i+2], b3 = (quint8)data[i+3];
        int version = (b1 >> 3) & 0x3;
        int layer   = (b1 >> 1) & 0x3;
        if (layer != 1) continue;
        int brIdx   = (b2 >> 4) & 0xF;
        int srIdx   = (b2 >> 2) & 0x3;
        int chMode  = (b3 >> 6) & 0x3;
        if (brIdx == 0 || brIdx == 15 || srIdx == 3) continue;
        int bitrate = (version == 3) ? bitrateTableV1L3[brIdx]
                                     : bitrateTableV2L3[brIdx];
        int sr = (version == 3) ? srTable[srIdx]
               : (version == 2) ? srTableV2[srIdx]
                                : srTableV25[srIdx];
        int ch = (chMode == 3) ? 1 : 2;
        if (bitrate > 0 && sr > 0) return {bitrate, sr, ch};
    }
    return {};
}

// ── FLAC ─────────────────────────────────────────────────────────────────────
struct FlacInfo { int sampleRate{0}; int channels{0}; int bitsPerSample{0}; qint64 totalSamples{0}; };
static FlacInfo parseFlac(const QByteArray &data) {
    if (data.size() < 42 || !data.startsWith("fLaC")) return {};
    if ((quint8)data[4] & 0x7F) return {}; // not STREAMINFO
    const quint8 *s = (const quint8 *)data.constData() + 8;
    int sr       = (s[10] << 12) | (s[11] << 4) | (s[12] >> 4);
    int ch       = ((s[12] >> 1) & 0x7) + 1;
    int bps      = (((s[12] & 0x1) << 4) | (s[13] >> 4)) + 1;
    qint64 total = ((qint64)(s[13] & 0xF) << 32) | ((qint64)s[14] << 24)
                 | ((qint64)s[15] << 16) | ((qint64)s[16] << 8) | s[17];
    return {sr, ch, bps, total};
}

// ── Ogg Vorbis ───────────────────────────────────────────────────────────────
struct OggInfo { int sampleRate{0}; int channels{0}; int bitrateNominal{0}; };
static OggInfo parseOggVorbis(const QByteArray &data) {
    int idx = data.indexOf("OggS");
    while (idx >= 0 && idx + 27 < data.size()) {
        int p = data.indexOf("\x01vorbis", idx);
        if (p < 0) break;
        if (p + 30 >= data.size()) break;
        const quint8 *v = (const quint8 *)data.constData() + p + 7;
        int version = v[0]|(v[1]<<8)|(v[2]<<16)|(v[3]<<24);
        if (version != 0) { idx = data.indexOf("OggS", idx + 1); continue; }
        int ch = v[4];
        int sr = v[5]|(v[6]<<8)|(v[7]<<16)|(v[8]<<24);
        int bn = v[13]|(v[14]<<8)|(v[15]<<16)|(v[16]<<24);
        return {sr, ch, bn / 1000};
    }
    return {};
}

// ── Opus ─────────────────────────────────────────────────────────────────────
struct OpusInfo { int sampleRate{0}; int channels{0}; };
static OpusInfo parseOpus(const QByteArray &data) {
    int idx = data.indexOf("OpusHead");
    // Reads v[0] (channels) and v[4..7] (sample rate) = data[idx+9 .. idx+16],
    // so the buffer must hold at least idx+17 bytes.
    if (idx < 0 || !inBounds(data, idx + 9, 8)) return {};
    const quint8 *v = (const quint8 *)data.constData() + idx + 9;
    int ch = v[0];
    int sr = v[4]|(v[5]<<8)|(v[6]<<16)|(v[7]<<24);
    if (sr == 0) sr = 48000;
    return {sr, ch};
}

// ── WAV (RIFF) ───────────────────────────────────────────────────────────────
struct WavInfo { int sampleRate{0}; int channels{0}; int bitsPerSample{0}; int bitrateKbps{0}; };
static WavInfo parseWav(const QByteArray &data) {
    if (data.size() < 12 || !data.startsWith("RIFF")
        || std::memcmp(data.constData() + 8, "WAVE", 4) != 0)
        return {};
    int off = 12;
    int guard = 0;
    while (inBounds(data, off, 8)) {
        if (++guard > 4096) break;        // bound walk; crafted file can't spin the GUI
        const char *id = data.constData() + off;
        quint32 sz = rdU32LE(data, off + 4);
        int body = off + 8;
        if (std::memcmp(id, "fmt ", 4) == 0) {
            if (!inBounds(data, body, 16)) return {};
            WavInfo w;
            w.channels       = rdU16LE(data, body + 2);
            w.sampleRate     = (int)rdU32LE(data, body + 4);
            quint32 byteRate = rdU32LE(data, body + 8);
            w.bitsPerSample  = rdU16LE(data, body + 14);
            w.bitrateKbps    = (int)((quint64)byteRate * 8 / 1000);
            if (w.sampleRate <= 0 || w.channels <= 0) return {};
            return w;
        }
        quint32 advance = sz + (sz & 1u);
        if (advance == 0) break;
        // Reject chunk sizes that overflow a signed int: off is int, and a
        // negative (int)advance would jump the cursor backwards onto an earlier
        // offset and spin forever on a crafted file.
        if (advance > (quint32)INT_MAX) break;
        if ((quint64)body + advance < (quint64)body) break;
        off = body + (int)advance;
    }
    return {};
}

// ── AIFF (FORM/AIFF) ─────────────────────────────────────────────────────────
struct AiffInfo { int sampleRate{0}; int channels{0}; int bitsPerSample{0}; int bitrateKbps{0}; };
static int read80BitFloat(const QByteArray &d, int off) {
    if (!inBounds(d, off, 10)) return 0;
    const quint8 *p = (const quint8 *)d.constData() + off;
    int exponent = ((p[0] & 0x7F) << 8) | p[1];
    quint64 mantissa = 0;
    for (int i = 0; i < 8; ++i) mantissa = (mantissa << 8) | p[2 + i];
    if (exponent == 0 && mantissa == 0) return 0;
    exponent -= 16383;
    int shift = exponent - 63;
    double val = (double)mantissa;
    while (shift > 0) { val *= 2.0; --shift; }
    while (shift < 0) { val /= 2.0; ++shift; }
    if (val <= 0 || val > 2'000'000.0) return 0;
    return (int)(val + 0.5);
}
static AiffInfo parseAiff(const QByteArray &data) {
    if (data.size() < 12 || !data.startsWith("FORM")) return {};
    const char *form = data.constData() + 8;
    if (std::memcmp(form, "AIFF", 4) != 0 && std::memcmp(form, "AIFC", 4) != 0)
        return {};
    int off = 12;
    int guard = 0;
    while (inBounds(data, off, 8)) {
        if (++guard > 4096) break;        // bound walk; crafted file can't spin the GUI
        const char *id = data.constData() + off;
        quint32 sz = rdU32BE(data, off + 4);
        int body = off + 8;
        if (std::memcmp(id, "COMM", 4) == 0) {
            if (!inBounds(data, body, 18)) return {};
            AiffInfo a;
            a.channels      = (qint16)rdU16BE(data, body);
            a.bitsPerSample = rdU16BE(data, body + 6);
            a.sampleRate    = read80BitFloat(data, body + 8);
            if (a.sampleRate <= 0 || a.channels <= 0) return {};
            a.bitrateKbps   = (int)((qint64)a.sampleRate * a.channels * a.bitsPerSample / 1000);
            return a;
        }
        quint32 advance = sz + (sz & 1u);
        if (advance == 0) break;
        // Reject chunk sizes that overflow a signed int (see parseWav): a negative
        // (int)advance would rewind off and spin forever on a crafted file.
        if (advance > (quint32)INT_MAX) break;
        if ((quint64)body + advance < (quint64)body) break;
        off = body + (int)advance;
    }
    return {};
}

// ── AAC raw (ADTS) ───────────────────────────────────────────────────────────
struct AdtsInfo { int sampleRate{0}; int channels{0}; int bitrateKbps{0}; };
static AdtsInfo parseAdts(const QByteArray &data) {
    static const int srTable[] = {96000,88200,64000,48000,44100,32000,24000,
                                  22050,16000,12000,11025,8000,7350,0,0,0};
    for (int i = 0; i + 7 < data.size(); ++i) {
        quint8 b0 = (quint8)data[i], b1 = (quint8)data[i+1];
        if (b0 != 0xFF || (b1 & 0xF6) != 0xF0) continue;
        quint8 b2 = (quint8)data[i+2], b3 = (quint8)data[i+3];
        int srIdx = (b2 >> 2) & 0xF;
        int chCfg = ((b2 & 0x1) << 2) | ((b3 >> 6) & 0x3);
        int sr = srTable[srIdx];
        if (sr == 0 || chCfg == 0) continue;
        quint8 b4 = (quint8)data[i+4], b5 = (quint8)data[i+5];
        int frameLen = ((b3 & 0x3) << 11) | (b4 << 3) | (b5 >> 5);
        if (frameLen < 7) continue;
        AdtsInfo a;
        a.sampleRate = sr;
        a.channels   = (chCfg == 7) ? 8 : chCfg;
        a.bitrateKbps = (int)((qint64)frameLen * 8 * sr / 1024 / 1000);
        return a;
    }
    return {};
}

// ── WMA (ASF) ────────────────────────────────────────────────────────────────
struct AsfInfo { int sampleRate{0}; int channels{0}; int bitsPerSample{0}; int bitrateKbps{0}; };
static const quint8 kAsfHeader[16] = {
    0x30,0x26,0xB2,0x75,0x8E,0x66,0xCF,0x11,0xA6,0xD9,0x00,0xAA,0x00,0x62,0xCE,0x6C};
static const quint8 kAsfStreamProps[16] = {
    0x91,0x07,0xDC,0xB7,0xB7,0xA9,0xCF,0x11,0x8E,0xE6,0x00,0xC0,0x0C,0x20,0x53,0x65};
static const quint8 kAsfAudioMedia[16] = {
    0x40,0x9E,0x69,0xF8,0x4D,0x5B,0xCF,0x11,0xA8,0xFD,0x00,0x80,0x5F,0x5C,0x44,0x2B};
static AsfInfo parseAsf(const QByteArray &data) {
    if (data.size() < 30 || std::memcmp(data.constData(), kAsfHeader, 16) != 0)
        return {};
    int off = 30;
    int guard = 0;
    while (inBounds(data, off, 24)) {
        if (++guard > 1024) break;
        quint64 objSize = rdU64LE(data, off + 16);
        if (objSize < 24) break;
        if ((quint64)off + objSize > (quint64)data.size())
            objSize = data.size() - off;
        if (std::memcmp(data.constData() + off, kAsfStreamProps, 16) == 0) {
            int body = off + 24;
            if (inBounds(data, body, 54)
                && std::memcmp(data.constData() + body, kAsfAudioMedia, 16) == 0) {
                int tsLen = (int)rdU32LE(data, body + 40);
                int ts = body + 54;
                if (tsLen >= 16 && inBounds(data, ts, 16)) {
                    AsfInfo a;
                    a.channels       = rdU16LE(data, ts + 2);
                    a.sampleRate     = (int)rdU32LE(data, ts + 4);
                    quint32 avgBytes = rdU32LE(data, ts + 8);
                    a.bitsPerSample  = rdU16LE(data, ts + 14);
                    a.bitrateKbps    = (int)((quint64)avgBytes * 8 / 1000);
                    if (a.sampleRate > 0 && a.channels > 0) return a;
                }
            }
        }
        if (off + (int)objSize <= off) break;
        off += (int)objSize;
    }
    return {};
}

// ════════════════════════════════════════════════════════════════════════════
//  ISO-BMFF box walker (shared: MP4/MOV/M4A video+audio, CR3 raw)
// ════════════════════════════════════════════════════════════════════════════

// Locate a direct child box `type` within [start, end). Returns body offset and
// sets body-end; -1 if not found. Bounds-safe; rejects malformed/overflowing sizes.
static int findBox(const QByteArray &d, int start, int end,
                   const char *type, int &outBody, int &outBodyEnd) {
    int off = start;
    int guard = 0;
    while (off + 8 <= end && off + 8 <= d.size()) {
        if (++guard > 4096) break;
        quint32 sz = rdU32BE(d, off);
        int header = 8;
        qint64 boxSize = sz;
        if (sz == 1) {
            if (!inBounds(d, off + 8, 8)) break;
            quint64 big = ((quint64)rdU32BE(d, off + 8) << 32) | rdU32BE(d, off + 12);
            if (big > (quint64)INT_MAX) break;
            boxSize = (qint64)big;
            header = 16;
        } else if (sz == 0) {
            boxSize = end - off;
        }
        if (boxSize < header) break;
        if (off + boxSize > end) break;
        if (std::memcmp(d.constData() + off + 4, type, 4) == 0) {
            outBody    = off + header;
            outBodyEnd = off + (int)boxSize;
            return outBody;
        }
        off += (int)boxSize;
    }
    return -1;
}

// Map an MP4 sample-entry fourcc to a display codec string (fixed literals only).
static QString mp4VideoCodec(const char *fourcc) {
    if (!std::memcmp(fourcc, "avc1", 4) || !std::memcmp(fourcc, "avc3", 4)) return QStringLiteral("H.264");
    if (!std::memcmp(fourcc, "hev1", 4) || !std::memcmp(fourcc, "hvc1", 4)) return QStringLiteral("H.265");
    if (!std::memcmp(fourcc, "av01", 4)) return QStringLiteral("AV1");
    if (!std::memcmp(fourcc, "vp09", 4)) return QStringLiteral("VP9");
    if (!std::memcmp(fourcc, "mp4v", 4)) return QStringLiteral("MPEG-4");
    return QString();
}
// Recognised video sample-entry fourccs to scan for inside a stsd box.
static const char *kMp4VideoFourccs[] = {"avc1","avc3","hev1","hvc1","av01","vp09","mp4v"};

struct Mp4Info {
    int sampleRate{0}; int channels{0}; int bitsPerSample{0}; int audioBitrateKbps{0};
    int width{0}; int height{0}; QString videoCodec; int fps{0};
    int durationSec{0};
};
static Mp4Info parseMp4(const QByteArray &data) {
    Mp4Info m;
    int b, e;
    if (findBox(data, 0, data.size(), "moov", b, e) < 0) return {};
    int moovB = b, moovE = e;

    // mvhd duration (whole movie) as a fallback.
    int mvB, mvE;
    if (findBox(data, moovB, moovE, "mvhd", mvB, mvE) >= 0 && inBounds(data, mvB, 4)) {
        quint8 ver = (quint8)data[mvB];
        if (ver == 1 && inBounds(data, mvB + 28, 0) && mvB + 28 <= mvE && inBounds(data, mvB + 20, 12)) {
            quint64 ts = rdU32BE(data, mvB + 20);
            quint64 du = ((quint64)rdU32BE(data, mvB + 24) << 32) | rdU32BE(data, mvB + 28);
            if (ts > 0 && du > 0) m.durationSec = (int)(du / ts);
        } else if (inBounds(data, mvB + 20, 8)) {
            quint64 ts = rdU32BE(data, mvB + 12);
            quint64 du = rdU32BE(data, mvB + 16);
            if (ts > 0 && du > 0) m.durationSec = (int)(du / ts);
        }
    }

    // Walk every trak: a movie has separate video and audio traks.
    int scan = moovB;
    int trakGuard = 0;
    int trB, trE;
    while (findBox(data, scan, moovE, "trak", trB, trE) >= 0) {
        if (++trakGuard > 16) break;
        scan = trE;                                  // next trak after this one

        int mdB, mdE;
        if (findBox(data, trB, trE, "mdia", mdB, mdE) < 0) continue;

        // tkhd: track width/height (16.16 fixed) — video traks only carry nonzero.
        int tkB, tkE;
        int trackW = 0, trackH = 0;
        if (findBox(data, trB, trE, "tkhd", tkB, tkE) >= 0 && inBounds(data, tkB, 4)) {
            quint8 ver = (quint8)data[tkB];
            int wOff = (ver == 1) ? tkB + 88 : tkB + 76; // width@.., height@+4
            if (inBounds(data, wOff, 8)) {
                trackW = (int)(rdU32BE(data, wOff) >> 16);
                trackH = (int)(rdU32BE(data, wOff + 4) >> 16);
            }
        }

        int miB, miE;
        if (findBox(data, mdB, mdE, "minf", miB, miE) < 0) continue;
        int stB, stE;
        if (findBox(data, miB, miE, "stbl", stB, stE) < 0) continue;
        int sdB, sdE;
        if (findBox(data, stB, stE, "stsd", sdB, sdE) < 0) continue;
        if (!inBounds(data, sdB, 8)) continue;
        int entryOff = sdB + 8;

        // Audio sample entry?
        int seB, seE;
        bool aac  = (findBox(data, entryOff, sdE, "mp4a", seB, seE) >= 0);
        bool alac = !aac && (findBox(data, entryOff, sdE, "alac", seB, seE) >= 0);
        if (aac || alac) {
            if (inBounds(data, seB + 16, 4)) {
                m.channels      = rdU16BE(data, seB + 8);
                m.bitsPerSample = rdU16BE(data, seB + 10);
                m.sampleRate    = (int)(rdU32BE(data, seB + 16) >> 16);
            }
            if (aac) {
                int esB, esE;
                if (findBox(data, seB + 20, seE, "esds", esB, esE) >= 0) {
                    for (int p = esB; p + 13 < esE && p + 13 < data.size(); ++p) {
                        if ((quint8)data[p] == 0x04) {
                            quint32 avg = rdU32BE(data, p + 9);
                            if (avg > 0 && avg < 100'000'000u) {
                                m.audioBitrateKbps = (int)(avg / 1000);
                                break;
                            }
                        }
                    }
                }
            }
            continue;
        }

        // Video sample entry?
        for (const char *fourcc : kMp4VideoFourccs) {
            int vB, vE;
            if (findBox(data, entryOff, sdE, fourcc, vB, vE) < 0) continue;
            // VisualSampleEntry: ...(reserved 16)... width(u16)@24 height(u16)@26
            if (inBounds(data, vB + 28, 0) && inBounds(data, vB + 24, 4)) {
                int w = rdU16BE(data, vB + 24);
                int h = rdU16BE(data, vB + 26);
                if (w > 0 && h > 0) { m.width = w; m.height = h; }
            }
            if (m.width == 0 && trackW > 0) { m.width = trackW; m.height = trackH; }
            m.videoCodec = mp4VideoCodec(fourcc);

            // fps from stts (sample_count / track duration) when both known.
            int sttsB, sttsE;
            if (findBox(data, stB, stE, "stts", sttsB, sttsE) >= 0
                && inBounds(data, sttsB, 8)) {
                quint32 entries = rdU32BE(data, sttsB + 4);
                quint64 totalSamples = 0;
                int p = sttsB + 8;
                for (quint32 i = 0; i < entries && inBounds(data, p, 8) && i < 4096; ++i, p += 8)
                    totalSamples += rdU32BE(data, p);
                // mdhd timescale+duration for this media.
                int mhB, mhE;
                if (findBox(data, mdB, mdE, "mdhd", mhB, mhE) >= 0 && inBounds(data, mhB, 4)) {
                    quint8 ver = (quint8)data[mhB];
                    quint64 ts = 0, du = 0;
                    if (ver == 1 && inBounds(data, mhB + 28, 0) && inBounds(data, mhB + 20, 12)) {
                        ts = rdU32BE(data, mhB + 20);
                        du = ((quint64)rdU32BE(data, mhB + 24) << 32) | rdU32BE(data, mhB + 28);
                    } else if (inBounds(data, mhB + 16, 4)) {
                        ts = rdU32BE(data, mhB + 12);
                        du = rdU32BE(data, mhB + 16);
                    }
                    if (ts > 0 && du > 0) {
                        double sec = (double)du / ts;
                        if (sec > 0 && totalSamples > 0)
                            m.fps = (int)((double)totalSamples / sec + 0.5);
                        if (m.durationSec == 0) m.durationSec = (int)sec;
                    }
                }
            }
            break;
        }
    }
    return m;
}

// ════════════════════════════════════════════════════════════════════════════
//  VIDEO — Matroska/WebM, AVI, FLV
// ════════════════════════════════════════════════════════════════════════════

struct VideoInfo { int width{0}; int height{0}; QString codec; int fps{0}; int durationSec{0}; };

// ── Matroska / WebM (EBML) ───────────────────────────────────────────────────
// Read an EBML variable-length integer at `off`. `maskLength` removes the marker
// bits to yield the raw value (used for element data sizes). Returns bytes
// consumed in `len`; 0 on malformed/out-of-bounds.
static quint64 ebmlVint(const QByteArray &d, int off, int &len, bool stripMarker) {
    len = 0;
    if (!inBounds(d, off, 1)) return 0;
    quint8 first = (quint8)d[off];
    if (first == 0) return 0;
    int n = 1;
    quint8 mask = 0x80;
    while (n <= 8 && !(first & mask)) { mask >>= 1; ++n; }
    if (n > 8 || !inBounds(d, off, n)) { len = 0; return 0; }
    quint64 v = stripMarker ? (first & (mask - 1)) : first;
    for (int i = 1; i < n; ++i) v = (v << 8) | (quint8)d[off + i];
    len = n;
    return v;
}

static QString matroskaCodec(const QByteArray &id) {
    if (id.startsWith("V_MPEG4/ISO/AVC")) return QStringLiteral("H.264");
    if (id.startsWith("V_MPEGH/ISO/HEVC")) return QStringLiteral("H.265");
    if (id.startsWith("V_AV1")) return QStringLiteral("AV1");
    if (id.startsWith("V_VP9")) return QStringLiteral("VP9");
    if (id.startsWith("V_VP8")) return QStringLiteral("VP8");
    if (id.startsWith("V_MPEG4")) return QStringLiteral("MPEG-4");
    return QString();
}

// Recursive descent over EBML master elements, collecting video track props.
// Depth/element caps prevent pathological nesting and zero-size loops.
static void matroskaWalk(const QByteArray &d, int start, int end, int depth,
                         VideoInfo &vi, double &durationRaw, double &timecodeScale) {
    if (depth > 12) return;
    int off = start;
    int guard = 0;
    while (off < end) {
        if (++guard > 8192) break;
        int idLen = 0;
        quint64 id = ebmlVint(d, off, idLen, false);   // keep marker for IDs
        if (idLen == 0) break;
        int szOff = off + idLen;
        int szLen = 0;
        quint64 size = ebmlVint(d, szOff, szLen, true);
        if (szLen == 0) break;
        int body = szOff + szLen;
        if (size == 0 && idLen + szLen == 0) break;
        // Unknown-size (all-ones) elements: bail rather than guess.
        if (body > end || (quint64)body + size > (quint64)end) {
            // clamp to end for top-level streaming; otherwise stop
            if (body > end) break;
            size = end - body;
        }
        int bodyEnd = body + (int)size;

        switch (id) {
            case 0x18538067: // Segment
            case 0x1654AE6B: // Tracks
            case 0xAE:       // TrackEntry
            case 0xE0:       // Video
            case 0x1549A966: // Info
                matroskaWalk(d, body, bodyEnd, depth + 1, vi, durationRaw, timecodeScale);
                break;
            case 0xB0: // PixelWidth
                if (inBounds(d, body, (int)size) && size <= 8) {
                    quint64 w = 0; for (int i = 0; i < (int)size; ++i) w = (w<<8)|(quint8)d[body+i];
                    if (w > 0) vi.width = (int)w;
                }
                break;
            case 0xBA: // PixelHeight
                if (inBounds(d, body, (int)size) && size <= 8) {
                    quint64 h = 0; for (int i = 0; i < (int)size; ++i) h = (h<<8)|(quint8)d[body+i];
                    if (h > 0) vi.height = (int)h;
                }
                break;
            case 0x86: // CodecID
                if (inBounds(d, body, (int)size) && size < 64 && vi.codec.isEmpty()) {
                    QByteArray cid(d.constData() + body, (int)size);
                    QString c = matroskaCodec(cid);
                    if (!c.isEmpty()) vi.codec = c;
                }
                break;
            case 0x2AD7B1: // TimecodeScale (ns per tick)
                if (inBounds(d, body, (int)size) && size <= 8) {
                    quint64 t = 0; for (int i = 0; i < (int)size; ++i) t = (t<<8)|(quint8)d[body+i];
                    if (t > 0) timecodeScale = (double)t;
                }
                break;
            case 0x4489: // Duration (float, in timecode-scale units)
                if (size == 4 && inBounds(d, body, 4)) {
                    quint32 bits = rdU32BE(d, body); float f; std::memcpy(&f, &bits, 4);
                    durationRaw = f;
                } else if (size == 8 && inBounds(d, body, 8)) {
                    quint64 bits = ((quint64)rdU32BE(d, body) << 32) | rdU32BE(d, body + 4);
                    double dd; std::memcpy(&dd, &bits, 8); durationRaw = dd;
                }
                break;
            default: break;
        }
        if (bodyEnd <= off) break;                     // no progress
        off = bodyEnd;
    }
}

static VideoInfo parseMatroska(const QByteArray &data) {
    // EBML header magic 0x1A45DFA3.
    if (data.size() < 4 || (quint8)data[0] != 0x1A || (quint8)data[1] != 0x45
        || (quint8)data[2] != 0xDF || (quint8)data[3] != 0xA3)
        return {};
    VideoInfo vi;
    double durationRaw = 0, timecodeScale = 1'000'000.0; // default 1ms
    matroskaWalk(data, 0, data.size(), 0, vi, durationRaw, timecodeScale);
    if (durationRaw > 0)
        vi.durationSec = (int)(durationRaw * timecodeScale / 1e9 + 0.5);
    return vi;
}

// ── AVI (RIFF) ───────────────────────────────────────────────────────────────
static QString aviCodec(quint32 fourcc) {
    char c[5] = {(char)(fourcc & 0xFF), (char)((fourcc>>8)&0xFF),
                 (char)((fourcc>>16)&0xFF), (char)((fourcc>>24)&0xFF), 0};
    QByteArray f = QByteArray(c, 4).toUpper();
    if (f == "H264" || f == "X264" || f == "AVC1") return QStringLiteral("H.264");
    if (f == "HEVC" || f == "HVC1" || f == "X265") return QStringLiteral("H.265");
    if (f == "XVID" || f == "DIVX" || f == "DX50" || f == "MP4V") return QStringLiteral("MPEG-4");
    if (f == "MJPG") return QStringLiteral("Motion JPEG");
    if (f == "VP80") return QStringLiteral("VP8");
    if (f == "VP90") return QStringLiteral("VP9");
    return QString();
}
static VideoInfo parseAvi(const QByteArray &data) {
    if (data.size() < 12 || !data.startsWith("RIFF")
        || std::memcmp(data.constData() + 8, "AVI ", 4) != 0)
        return {};
    VideoInfo vi;
    // Find the 'avih' main header anywhere in the (header-region) buffer.
    int ah = data.indexOf("avih");
    if (ah >= 0 && inBounds(data, ah + 4, 40)) {
        int b = ah + 8; // avih body after fourcc+size
        if (inBounds(data, b, 40)) {
            quint32 usecPerFrame = rdU32LE(data, b + 0);
            quint32 totalFrames  = rdU32LE(data, b + 16);
            vi.width  = (int)rdU32LE(data, b + 32);
            vi.height = (int)rdU32LE(data, b + 36);
            if (usecPerFrame > 0) {
                vi.fps = (int)(1'000'000.0 / usecPerFrame + 0.5);
                if (totalFrames > 0)
                    vi.durationSec = (int)((double)totalFrames * usecPerFrame / 1e6);
            }
        }
    }
    // Codec fourcc lives in strf/BITMAPINFOHEADER biCompression. Find 'strf'
    // then read biCompression at body+16.
    int sf = data.indexOf("strf");
    if (sf >= 0 && inBounds(data, sf + 8 + 20, 0) && inBounds(data, sf + 8 + 16, 4)) {
        quint32 comp = rdU32LE(data, sf + 8 + 16);
        if (comp != 0) vi.codec = aviCodec(comp);
    }
    return vi;
}

// ── FLV ──────────────────────────────────────────────────────────────────────
static VideoInfo parseFlv(const QByteArray &data) {
    if (data.size() < 9 || !data.startsWith("FLV")) return {};
    VideoInfo vi;
    // Walk tags: header(9) + PreviousTagSize0(4), then tags:
    //   type(1) dataSize(3 BE) timestamp(3) tsExt(1) streamId(3) data...
    int dataOffset = (int)rdU32BE(data, 5);
    int off = (dataOffset >= 9 ? dataOffset : 9) + 4;
    int guard = 0;
    while (inBounds(data, off, 11)) {
        if (++guard > 64) break;
        quint8 type = (quint8)data[off];
        int dataSize = ((quint8)data[off+1] << 16) | ((quint8)data[off+2] << 8) | (quint8)data[off+3];
        int body = off + 11;
        if (dataSize <= 0 || !inBounds(data, body, 1)) break;
        if (type == 0x09) { // video tag
            quint8 vh = (quint8)data[body];
            int codecId = vh & 0x0F;
            switch (codecId) {
                case 7: vi.codec = QStringLiteral("H.264"); break;
                case 12: vi.codec = QStringLiteral("H.265"); break;
                case 2: vi.codec = QStringLiteral("H.263"); break;
                case 4: case 5: vi.codec = QStringLiteral("VP6"); break;
                default: break;
            }
            break; // first video tag's codec is enough; dimensions need SPS parse (skip)
        }
        int adv = 11 + dataSize + 4; // tag + trailing PreviousTagSize
        if (adv <= 0) break;
        off += adv;
    }
    return vi;
}

// ════════════════════════════════════════════════════════════════════════════
//  IMAGE
// ════════════════════════════════════════════════════════════════════════════

struct ImageInfo { int width{0}; int height{0}; int bitDepth{0}; QString colorType; };

static ImageInfo parsePng(const QByteArray &d) {
    static const quint8 sig[8] = {0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A};
    if (d.size() < 33 || std::memcmp(d.constData(), sig, 8) != 0) return {};
    if (std::memcmp(d.constData() + 12, "IHDR", 4) != 0) return {};
    ImageInfo im;
    im.width    = (int)rdU32BE(d, 16);
    im.height   = (int)rdU32BE(d, 20);
    im.bitDepth = (quint8)d[24];
    switch ((quint8)d[25]) {
        case 0: im.colorType = QStringLiteral("Grayscale"); break;
        case 2: im.colorType = QStringLiteral("RGB"); break;
        case 3: im.colorType = QStringLiteral("Indexed"); break;
        case 4: im.colorType = QStringLiteral("Grayscale+Alpha"); break;
        case 6: im.colorType = QStringLiteral("RGBA"); break;
        default: break;
    }
    if (im.width <= 0 || im.height <= 0) return {};
    return im;
}

static ImageInfo parseJpeg(const QByteArray &d) {
    if (d.size() < 4 || (quint8)d[0] != 0xFF || (quint8)d[1] != 0xD8) return {};
    int off = 2;
    int guard = 0;
    while (inBounds(d, off, 4)) {
        if (++guard > 1024) break;
        if ((quint8)d[off] != 0xFF) { ++off; continue; }
        quint8 marker = (quint8)d[off+1];
        if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
            off += 2; continue; // standalone markers, no length
        }
        int len = rdU16BE(d, off + 2);
        if (len < 2) break;
        // SOF markers carry frame dimensions (exclude DHT/DAC/JPG/restart).
        bool isSof = (marker >= 0xC0 && marker <= 0xCF)
                     && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
        if (isSof && inBounds(d, off + 5, 5)) {
            ImageInfo im;
            im.bitDepth = (quint8)d[off + 4];          // sample precision
            im.height   = rdU16BE(d, off + 5);
            im.width    = rdU16BE(d, off + 7);
            if (im.width > 0 && im.height > 0) return im;
        }
        off += 2 + len;
    }
    return {};
}

static ImageInfo parseGif(const QByteArray &d) {
    if (d.size() < 10 || (!d.startsWith("GIF87a") && !d.startsWith("GIF89a"))) return {};
    ImageInfo im;
    im.width  = rdU16LE(d, 6);
    im.height = rdU16LE(d, 8);
    if (im.width <= 0 || im.height <= 0) return {};
    return im;
}

static ImageInfo parseBmp(const QByteArray &d) {
    if (d.size() < 30 || !d.startsWith("BM")) return {};
    ImageInfo im;
    im.width    = (int)rdU32LE(d, 18);
    im.height   = qAbs((qint32)rdU32LE(d, 22));
    im.bitDepth = rdU16LE(d, 28);
    if (im.width <= 0 || im.height <= 0) return {};
    return im;
}

static ImageInfo parseWebp(const QByteArray &d) {
    if (d.size() < 16 || !d.startsWith("RIFF")
        || std::memcmp(d.constData() + 8, "WEBP", 4) != 0)
        return {};
    ImageInfo im;
    const char *fmt = d.constData() + 12;
    if (!std::memcmp(fmt, "VP8 ", 4) && inBounds(d, 26, 4)) {
        // Lossy: 14-bit width/height at offset 26/28 (after frame tag).
        im.width  = (rdU16LE(d, 26) & 0x3FFF);
        im.height = (rdU16LE(d, 28) & 0x3FFF);
    } else if (!std::memcmp(fmt, "VP8L", 4) && inBounds(d, 21, 5)) {
        // Lossless: 14-bit each packed after 1-byte signature 0x2F at offset 20.
        quint32 bits = rdU32LE(d, 21);
        im.width  = (int)((bits & 0x3FFF) + 1);
        im.height = (int)(((bits >> 14) & 0x3FFF) + 1);
    } else if (!std::memcmp(fmt, "VP8X", 4) && inBounds(d, 24, 6)) {
        // Extended: 24-bit width-1/height-1 at offset 24/27.
        im.width  = (int)((rdU32LE(d, 24) & 0xFFFFFF) + 1);
        im.height = (int)(((rdU32LE(d, 26) >> 8) & 0xFFFFFF) + 1);
    }
    if (im.width <= 0 || im.height <= 0) return {};
    return im;
}

// ════════════════════════════════════════════════════════════════════════════
//  TIFF / RAW (shared IFD reader)
// ════════════════════════════════════════════════════════════════════════════

struct TiffInfo { int width{0}; int height{0}; int bitDepth{0};
                  QString make; QString model; };

// Parse a TIFF IFD chain starting at byte order mark. Walks SubIFDs (tag 330)
// to find the largest width/height (full-res for many raw formats), and reads
// EXIF Make/Model from IFD0. Endian per the II/MM mark. Fully bounds-checked.
static TiffInfo parseTiff(const QByteArray &d) {
    if (d.size() < 8) return {};
    bool le;
    if (d[0] == 'I' && d[1] == 'I') le = true;
    else if (d[0] == 'M' && d[1] == 'M') le = false;
    else return {};
    auto u16 = [&](int o) -> quint32 {
        if (!inBounds(d, o, 2)) return 0;
        return le ? rdU16LE(d, o) : rdU16BE(d, o);
    };
    auto u32 = [&](int o) -> quint32 {
        if (!inBounds(d, o, 4)) return 0;
        return le ? rdU32LE(d, o) : rdU32BE(d, o);
    };
    if (u16(2) != 42) return {};
    TiffInfo t;

    // Read scalar tag value (SHORT/LONG) regardless of type packing.
    auto tagValue = [&](int entry) -> quint32 {
        quint32 type = u16(entry + 2);
        int valOff = entry + 8;
        if (type == 3) return u16(valOff);     // SHORT
        return u32(valOff);                     // LONG / fallback
    };
    auto tagString = [&](int entry) -> QString {
        quint32 count = u32(entry + 4);
        if (count == 0 || count > 256) count = qMin<quint32>(count, 256);
        int valOff = entry + 8;
        // <=4 bytes inline, else pointer.
        int strOff = (count <= 4) ? valOff : (int)u32(valOff);
        if (!inBounds(d, strOff, (int)count)) return QString();
        return sanitizeText(QByteArray(d.constData() + strOff, (int)count));
    };

    // Walk IFD0 + any SubIFDs (one level), tracking largest dims found.
    int subIfds[16]; int subCount = 0;
    auto readIfd = [&](int ifdOff) {
        if (!inBounds(d, ifdOff, 2)) return;
        int n = (int)u16(ifdOff);
        if (n <= 0 || n > 512) return;
        for (int i = 0; i < n; ++i) {
            int entry = ifdOff + 2 + i * 12;
            if (!inBounds(d, entry, 12)) break;
            quint32 tag = u16(entry);
            switch (tag) {
                case 0x0100: { int v=(int)tagValue(entry); if (v>t.width)  t.width=v; } break;  // ImageWidth
                case 0x0101: { int v=(int)tagValue(entry); if (v>t.height) t.height=v; } break; // ImageLength
                case 0x0102: { int v=(int)tagValue(entry); if (v>t.bitDepth) t.bitDepth=v; } break; // BitsPerSample
                case 0x010F: if (t.make.isEmpty())  t.make  = tagString(entry); break; // Make
                case 0x0110: if (t.model.isEmpty()) t.model = tagString(entry); break; // Model
                case 0x014A: { // SubIFDs (one or more pointers)
                    quint32 cnt = u32(entry + 4);
                    int p = (cnt <= 1) ? entry + 8 : (int)u32(entry + 8);
                    for (quint32 k = 0; k < cnt && subCount < 16; ++k) {
                        int so = (cnt <= 1) ? (int)u32(entry + 8) : (int)u32(p + k * 4);
                        if (so > 0 && inBounds(d, so, 2)) subIfds[subCount++] = so;
                    }
                } break;
                default: break;
            }
        }
    };

    int ifd0 = (int)u32(4);
    if (ifd0 <= 0 || !inBounds(d, ifd0, 2)) return t;
    readIfd(ifd0);
    for (int i = 0; i < subCount; ++i) readIfd(subIfds[i]);
    return t;
}

} // namespace

// ════════════════════════════════════════════════════════════════════════════
//  PUBLIC API
// ════════════════════════════════════════════════════════════════════════════

namespace MediaMetadata {

bool mayNeedTailRange(const QString &contentType, const QString &ext) {
    // Only the MP4/MOV family can place `moov` after `mdat` (non-faststart).
    const QString ct = contentType.toLower();
    return ext == QLatin1String("m4a") || ext == QLatin1String("m4b")
        || ext == QLatin1String("mp4") || ext == QLatin1String("mov")
        || ext == QLatin1String("m4v")
        || ctHas(ct, "mp4") || ctHas(ct, "m4a") || ctHas(ct, "quicktime");
}

bool parse(const QByteArray &data, const QString &contentType,
           const QString &ext, qint64 fileSize, QVariantMap &info) {
    const QString ct = contentType.toLower();
    bool filled = false;
    auto setI = [&](const char *k, int v) {
        if (v > 0) { info[QLatin1String(k)] = v; filled = true; }
    };
    auto setS = [&](const char *k, const QString &v) {
        if (!v.isEmpty()) { info[QLatin1String(k)] = v; filled = true; }
    };

    // Classify by ext / content-type.
    auto isExt = [&](std::initializer_list<const char *> xs) {
        for (auto x : xs) if (ext == QLatin1String(x)) return true;
        return false;
    };

    // ── IMAGE ────────────────────────────────────────────────────────────────
    if (isExt({"png","jpg","jpeg","jpe","gif","webp","bmp","tif","tiff"})
        || ct.startsWith(QStringLiteral("image/"))) {
        ImageInfo im;
        if (isExt({"png"}) || ctHas(ct, "png")) im = parsePng(data);
        else if (isExt({"jpg","jpeg","jpe"}) || ctHas(ct, "jpeg")) im = parseJpeg(data);
        else if (isExt({"gif"}) || ctHas(ct, "gif")) im = parseGif(data);
        else if (isExt({"webp"}) || ctHas(ct, "webp")) im = parseWebp(data);
        else if (isExt({"bmp"}) || ctHas(ct, "bmp")) im = parseBmp(data);
        else if (isExt({"tif","tiff"}) || ctHas(ct, "tiff")) {
            auto t = parseTiff(data); im.width = t.width; im.height = t.height; im.bitDepth = t.bitDepth;
        }
        if (im.width <= 0) { // generic: sniff by magic
            if (data.startsWith("\x89PNG")) im = parsePng(data);
            else if (data.size() > 2 && (quint8)data[0]==0xFF && (quint8)data[1]==0xD8) im = parseJpeg(data);
        }
        setI("imageWidth", im.width);
        setI("imageHeight", im.height);
        setI("imageBitDepth", im.bitDepth);
        setS("imageColorType", im.colorType);
        return filled;
    }

    // ── RAW PHOTO ──────────────────────────────────────────────────────────────
    if (isExt({"cr2","nef","arw","dng","orf","rw2","pef","srw","raf","cr3"})) {
        TiffInfo t;
        if (ext == QLatin1String("cr3")) {
            auto mp = parseMp4(data);             // CR3 is ISO-BMFF
            // CR3 preview track may carry dims; fall through to EXIF for make/model.
            setI("imageWidth", mp.width);
            setI("imageHeight", mp.height);
            // CMT1 box holds a TIFF/EXIF blob — try a TIFF parse of the tail.
            t = parseTiff(data);
        } else {
            t = parseTiff(data);
            setI("imageWidth", t.width);
            setI("imageHeight", t.height);
            setI("imageBitDepth", t.bitDepth);
        }
        setS("cameraMake", t.make);
        setS("cameraModel", t.model);
        return filled;
    }

    // ── VIDEO ──────────────────────────────────────────────────────────────────
    if (isExt({"mp4","mov","m4v"}) || ctHas(ct, "mp4") || ctHas(ct, "quicktime")) {
        auto mp = parseMp4(data);
        setI("videoWidth", mp.width);
        setI("videoHeight", mp.height);
        setS("videoCodec", mp.videoCodec);
        setI("videoFps", mp.fps);
        setI("videoDurationSec", mp.durationSec);
        // Audio track in the same container.
        setI("audioSampleRate", mp.sampleRate);
        setI("audioChannels", mp.channels);
        if (mp.audioBitrateKbps > 0) setI("audioBitrateKbps", mp.audioBitrateKbps);
        return filled;
    }
    if (isExt({"mkv","webm"}) || ctHas(ct, "matroska") || ctHas(ct, "webm")) {
        auto vi = parseMatroska(data);
        setI("videoWidth", vi.width);
        setI("videoHeight", vi.height);
        setS("videoCodec", vi.codec);
        setI("videoDurationSec", vi.durationSec);
        return filled;
    }
    if (isExt({"avi"}) || ctHas(ct, "x-msvideo") || ctHas(ct, "avi")) {
        auto vi = parseAvi(data);
        setI("videoWidth", vi.width);
        setI("videoHeight", vi.height);
        setS("videoCodec", vi.codec);
        setI("videoFps", vi.fps);
        setI("videoDurationSec", vi.durationSec);
        return filled;
    }
    if (isExt({"flv"}) || ctHas(ct, "x-flv") || ctHas(ct, "flv")) {
        auto vi = parseFlv(data);
        setS("videoCodec", vi.codec);
        return filled;
    }

    // ── AUDIO ──────────────────────────────────────────────────────────────────
    if (ctHas(ct, "flac") || ext == QLatin1String("flac")) {
        auto fi = parseFlac(data);
        if (fi.sampleRate > 0) {
            setI("audioSampleRate", fi.sampleRate);
            setI("audioChannels", fi.channels);
            setI("audioBitsPerSample", fi.bitsPerSample);
            if (fileSize > 0 && fi.totalSamples > 0 && fi.sampleRate > 0) {
                double durationSec = (double)fi.totalSamples / fi.sampleRate;
                setI("audioDurationSec", (int)durationSec);
                setI("audioBitrateKbps", (int)((double)fileSize * 8 / durationSec / 1000));
            }
        }
    } else if (ctHas(ct, "ogg") || ext == QLatin1String("ogg") || ext == QLatin1String("oga")) {
        auto oi = parseOggVorbis(data);
        if (oi.sampleRate > 0) {
            setI("audioSampleRate", oi.sampleRate);
            setI("audioChannels", oi.channels);
            setI("audioBitrateKbps", oi.bitrateNominal);
        }
    } else if (ctHas(ct, "opus") || ext == QLatin1String("opus")) {
        auto op = parseOpus(data);
        if (op.sampleRate > 0) {
            setI("audioSampleRate", op.sampleRate);
            setI("audioChannels", op.channels);
        }
    } else if (ext == QLatin1String("wav") || ctHas(ct, "wav")
               || ctHas(ct, "x-wav") || ctHas(ct, "wave")) {
        auto w = parseWav(data);
        if (w.sampleRate > 0) {
            setI("audioSampleRate", w.sampleRate);
            setI("audioChannels", w.channels);
            setI("audioBitsPerSample", w.bitsPerSample);
            setI("audioBitrateKbps", w.bitrateKbps);
            if (w.bitrateKbps > 0 && fileSize > 0)
                setI("audioDurationSec", (int)((double)fileSize * 8 / (w.bitrateKbps * 1000)));
        }
    } else if (isExt({"aiff","aif","aifc"}) || ctHas(ct, "aiff")) {
        auto a = parseAiff(data);
        if (a.sampleRate > 0) {
            setI("audioSampleRate", a.sampleRate);
            setI("audioChannels", a.channels);
            setI("audioBitsPerSample", a.bitsPerSample);
            setI("audioBitrateKbps", a.bitrateKbps);
            if (a.bitrateKbps > 0 && fileSize > 0)
                setI("audioDurationSec", (int)((double)fileSize * 8 / (a.bitrateKbps * 1000)));
        }
    } else if (isExt({"m4a","m4b"}) || ctHas(ct, "m4a")) {
        auto mp = parseMp4(data);
        if (mp.sampleRate > 0) {
            setI("audioSampleRate", mp.sampleRate);
            setI("audioChannels", mp.channels);
            setI("audioBitsPerSample", mp.bitsPerSample);
            setI("audioDurationSec", mp.durationSec);
            if (mp.audioBitrateKbps > 0)
                setI("audioBitrateKbps", mp.audioBitrateKbps);
            else if (mp.durationSec > 0 && fileSize > 0)
                setI("audioBitrateKbps", (int)((double)fileSize * 8 / mp.durationSec / 1000));
        }
    } else if (ext == QLatin1String("wma") || ext == QLatin1String("asf")
               || ctHas(ct, "ms-asf") || ctHas(ct, "x-ms-wma")) {
        auto a = parseAsf(data);
        if (a.sampleRate > 0) {
            setI("audioSampleRate", a.sampleRate);
            setI("audioChannels", a.channels);
            setI("audioBitsPerSample", a.bitsPerSample);
            setI("audioBitrateKbps", a.bitrateKbps);
            if (a.bitrateKbps > 0 && fileSize > 0)
                setI("audioDurationSec", (int)((double)fileSize * 8 / (a.bitrateKbps * 1000)));
        }
    } else {
        // mp3 / aac(ADTS) / unknown: MP3 frame scan, then raw ADTS.
        auto mi = parseMp3Frame(data);
        if (mi.bitrate > 0) {
            setI("audioBitrateKbps", mi.bitrate);
            setI("audioSampleRate", mi.sampleRate);
            setI("audioChannels", mi.channels);
            if (fileSize > 0 && mi.bitrate > 0)
                setI("audioDurationSec", (int)((double)fileSize * 8 / (mi.bitrate * 1000)));
        } else {
            auto ad = parseAdts(data);
            if (ad.sampleRate > 0) {
                setI("audioSampleRate", ad.sampleRate);
                setI("audioChannels", ad.channels);
                setI("audioBitrateKbps", ad.bitrateKbps);
                if (ad.bitrateKbps > 0 && fileSize > 0)
                    setI("audioDurationSec", (int)((double)fileSize * 8 / (ad.bitrateKbps * 1000)));
            }
        }
    }

    return filled;
}

} // namespace MediaMetadata
