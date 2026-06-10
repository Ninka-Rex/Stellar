#pragma once

#include <QByteArray>
#include <QString>
#include <QVariantMap>

// Media header parsers. Every input here is untrusted server data (range-fetched
// bytes from an arbitrary host) — all parsers bounds-check before every read and
// never advance past the buffer. Output is numeric/short-string only, written
// into `info`.
namespace MediaMetadata {

// Parse media header bytes, dispatching on `contentType` / `ext` (lowercase
// extension, no leading dot). `fileSize` is the full Content-Length, used to
// estimate bitrate/duration for formats that don't carry explicit values.
//
// Writes any keys it can derive into `info`:
//   Audio: audioBitrateKbps, audioSampleRate, audioChannels,
//          audioBitsPerSample, audioDurationSec
//   Video: videoWidth, videoHeight, videoCodec, videoFps, videoDurationSec
//   Image: imageWidth, imageHeight, imageBitDepth, imageColorType
//   Photo: cameraMake, cameraModel  (raw/EXIF; sanitized printable ASCII)
//
// Returns true if at least one field was filled.
bool parse(const QByteArray &data, const QString &contentType,
           const QString &ext, qint64 fileSize, QVariantMap &info);

// True when the format's header can legally sit at the END of the file (MP4/MOV
// family with the `moov` box after `mdat`). The caller should retry parse() on a
// tail range when a head-range parse returns false.
bool mayNeedTailRange(const QString &contentType, const QString &ext);

} // namespace MediaMetadata
