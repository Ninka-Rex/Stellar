# Stellar Command Line Interface

Stellar supports IDM-compatible command line parameters for scripted and automated download management.

## Syntax

```
Stellar.exe /d URL [/p local_path] [/f local_file_name] [/q] [/n] [/a]
Stellar.exe /s
Stellar.exe <file.torrent> [/p local_path] [/q] [/n] [/a]
Stellar.exe <magnet:?xt=urn:btih:...> [/p local_path] [/q] [/n] [/a]
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `/d URL` | Download the file at `URL`. Also accepts `.torrent` file paths and `magnet:` URIs. |
| `/s` | Start the queue in scheduler (resumes all queued/paused downloads). |
| `/p local_path` | Directory to save the file. Defaults to the configured save folder if omitted. |
| `/f local_file_name` | Filename to save the file as. Overrides the server-supplied name. |
| `/q` | Quit Stellar after the download completes successfully. Only affects the first running copy. |
| `/n` | Silent mode. Stellar will not show any dialog or bring its window to the foreground. |
| `/a` | Add the file to the download queue but do not start downloading immediately. |

Parameters `/a`, `/n`, `/q`, `/f`, and `/p` apply when `/d URL` is specified, or when a `.torrent` file or `magnet:` URI is passed as a bare argument.

Both `/switch` and `-switch` prefix styles are accepted (e.g. `-d` and `/d` are equivalent).

## Behaviour

### Running instance detection

When a Stellar instance is already running, the CLI copy forwards the command to it over a local socket and exits immediately. The running instance carries out the download and honours `/q` when it completes.

When no instance is running, the CLI copy saves the download payload to a temporary drop file, launches the GUI, and exits. The GUI replays the payload on startup. With `/n`, the window opens minimized.

### `/s` with no running instance

Stellar is launched (minimized), and the CLI copy waits up to 20 seconds for it to start. Once connected, the start-scheduler command is forwarded and all queued downloads begin.

### `/q` (quit after download)

The application exits approximately 0.5 seconds after the target download reaches the Completed state. This delay allows in-flight database writes to flush. Only the specific download identified by `URL` triggers the quit; other concurrent downloads are not affected.

### `/a` (add only, do not start)

The download is created in the Queued state and placed in the default queue. It will not start until the queue is manually or programmatically started (e.g. via `/s`).

### `/n` (silent mode)

No UI interaction is triggered. The download is added directly without showing the Add URL dialog. For yt-dlp URLs (YouTube etc.), the format picker dialog is suppressed and the default format is used.

## Examples

Download a file using default settings:
```
Stellar.exe /d "https://example.com/archive.zip"
```

Download silently to a specific folder with a custom filename:
```
Stellar.exe /n /d "https://example.com/archive.zip" /p "C:\Downloads\Work" /f "project.zip"
```

Download silently and quit Stellar when done:
```
Stellar.exe /n /q /d "https://example.com/bigfile.iso"
```

Add a file to the queue without starting it:
```
Stellar.exe /a /d "https://example.com/file.exe"
```

Start the download queue (resume all queued downloads):
```
Stellar.exe /s
```

Open a `.torrent` file as a download:
```
Stellar.exe "C:\torrents\linux-distro.torrent"
```

Open a `.torrent` file silently, added to the queue without starting:
```
Stellar.exe "C:\torrents\movie.torrent" /n /a /p "D:\Movies"
```

Add a magnet link silently:
```
Stellar.exe /n /d "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
```

Add a magnet link directly (bare argument, same result):
```
Stellar.exe "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c" /p "D:\Downloads"
```

## Notes

- All parameters are case-insensitive.
- URL values containing spaces must be enclosed in double quotes.
- Local path values containing spaces must be enclosed in double quotes.
- The `/q` flag only causes an exit when there are no other active downloads at the time the target download completes, matching IDM's documented "first copy" semantics.
- Torrent (`.torrent`) files and magnet links can be passed as bare arguments or via `/d`. The torrent metadata dialog is shown interactively unless `/n` (silent mode) is used. The `/p`, `/q`, `/n`, and `/a` flags are honoured for torrent and magnet downloads where applicable. `/f` has no effect on torrents (filenames are determined by the torrent metadata).
