# Privacy Policy for Stellar Download Manager

Last updated: June 8, 2026

Applies to the Stellar Download Manager desktop application and its Chrome and Firefox extensions.

## Summary

Stellar does not collect, sell, or transmit your personal data to the developer. There are no analytics, ads, or behavioral tracking. Everything it processes stays on your device and is kept only as long as needed to make the app work.

## What Stellar Processes

Stellar processes the minimum needed to function locally: download links, filenames, status, app settings, and any authentication data (such as cookies) for downloads you ask it to handle. This data lives on your device and is retained only for as long as the feature requires - most of it is discarded as soon as a download completes or the app closes.

- **Downloads:** History and metadata are stored in local app data files so you can pause, resume, and re-download. Partial and completed files are written to the folders you choose.
- **Torrents:** When you use the built-in torrent client, your IP address is shared peer-to-peer with trackers and other peers - this is how BitTorrent works, not something Stellar adds. Torrent metadata and fast-resume data are stored locally only while a torrent is active or seeding.
- **Browser extensions:** Settings (enabled state, monitored extensions, excluded sites) are stored in the browser's local extension storage. To hand a download to the desktop app, the extension reads the current tab URL and, for authenticated downloads, the relevant cookies - passed straight to your local Stellar copy and not retained beyond that handoff.

The extensions request broad site access only to detect downloadable files and forward them to the native Stellar app. They do not send your browsing history or download activity anywhere remote.

## Network Connections

Stellar connects to remote servers only to do what you ask:

- Downloading files, torrents, or yt-dlp/grabber content from URLs you provide or approve
- Checking for updates and changelogs (GitHub servers)

Data may reach the file host you download from, trackers and peers for torrents you start, and any proxy you configure - never the developer.

## Retention and Control

Data stays on your device and is kept only as long as the relevant feature needs it. You can remove it any time by clearing download history, clearing extension storage, or uninstalling the app or extension.

## Children's Privacy

Stellar is not directed to children under 13, and does not collect personal information from anyone.

## Security

Security is taken seriously. Stellar is built to treat every server and downloaded file as hostile: untrusted input is sanitized and validated, downloads run without shell expansion, and the torrent client can be hardened to bind traffic to a chosen network interface. Data is kept local wherever practical.

That said, no software can guarantee absolute security, and Stellar is provided "as is" without any warranty - express or implied - including any implied warranty of merchantability or fitness for a particular purpose. You are responsible for securing your device, browser profile, and downloaded files.

## Changes

This policy may be updated from time to time; the latest version ships with the project source.

## Contact

Privacy questions: [admin@stellardownloadmanager.org](mailto:admin@stellardownloadmanager.org).
