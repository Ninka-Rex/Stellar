# Chrome Extension Manifests

This folder intentionally keeps two Chrome manifests:

- `manifest.json`
  Use this for local unpacked development.
  It includes a fixed `key` so Chrome keeps the extension ID stable:
  `kncomdlgkcaamlaaoloncdafbijdfcjo`
  Stellar's Windows native messaging registration is wired to that ID.

- `manifest.store.json`
  Use this for Chrome Web Store uploads.
  It is the same manifest but without the `key` field, because the Chrome Web
  Store rejects uploads that include `key`.

## Local testing

Load `extensions/chrome/` as an unpacked extension normally. Chrome reads
`manifest.json`, which preserves the fixed dev ID required by the native host.

## Web Store upload

Before zipping for upload, replace `manifest.json` in the upload copy with
`manifest.store.json` renamed to `manifest.json`.

The published Chrome Web Store extension will receive a different extension ID.
After that store ID is known, update the native messaging host allowlist for the
production build to include that published ID.
