# Stellar Download Manager Updates

Apr 10, 2026

Version 0.3.6 Beta is available

Windows and Firefox beta release only

This build is focused on the Windows app and Firefox integration.
Some features are still untested, some behavior may still be buggy, 
and this release should be treated as an early beta.

What's new in version 0.3.6?

- Added in-app update checking
- Added bundled Firefox `.xpi` packaging for Windows releases
- Improved status bar messaging for active downloads, finished downloads, 
  selected items, errors, speed limiter state, queue timing, and update checks
- Added configurable Last Try Date formatting with 12-hour and 24-hour time options

What's new in version 0.3.5?

- Added configurable Last Try Date formatting with 12-hour and 24-hour time options
- Added update checking infrastructure with status bar reporting
- Improved scheduler behavior and fixed dirty-state handling when switching queues
- Fixed pluralization and status text behavior in the bottom bar
- Fixed pending downloads so Download Later pauses active intercepted downloads immediately
- Added main window size persistence across launches

What's new in version 0.3.4?

- Fixed tips loading from Qt resources and fallback paths
- Improved status bar tip layout and spacing
- Tightened toolbar spacing and queue dropdown layout
- Fixed queue runtime behaviors for retries, limits, and completion actions
- Improved temporary file cleanup and pending download finalization

What's new in version 0.3.3?

- Improved scheduler dialog styling and Windows integration
- Fixed queue popup rendering issues and menu item insertion behavior
- Improved queue scheduling controls and scheduler form state tracking
- Added better status bar count formatting and selection text handling
