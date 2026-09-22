# Changelog

All notable user-visible changes to HouseControl PhotoScreen are recorded here.

## [Unreleased]

### Renamed

- Renamed the application from Studio Photos / StudioScreensaver to **HouseControl PhotoScreen**.
- Renamed the executable and SwiftPM product to `housecontrol-photoscreen`.
- Renamed the Swift target to `HouseControlPhotoScreen`.
- Renamed the macOS bundle icon resource to `HouseControlPhotoScreen.icns`.

### macOS application and presentation

- Replaced the text menu-bar label with the HouseControl application icon.
- Added a Quit button to the settings window.
- Kept the existing settings, slideshow, fullscreen, and icon behavior in the renamed bundle.

### Slideshow

- Added fade, slide, zoom, and Ken Burns transitions.
- Added left/right navigation.
- Added double-click-to-exit behavior.
- Added background indexing so slideshow startup does not perform a blocking folder scan.
- Added deletion OSD showing the deleted filename and full path.
- Moved Trash/permanent deletion work off the UI thread to prevent OneDrive operations from pausing the slideshow.

### Metadata and caching

- Added EXIF date caching.
- Added reverse-geocoded location display as city or suburb, state, country.
- Persisted metadata and geocoded locations in the HouseControl PhotoScreen cache directory.

### Input and deletion

- Added primary Delete and Forward Delete handling.
- Added optional learned secondary keys for keyboard, system/consumer, and mouse-button events.
- Added the single-button learning cycle: Learn Key, Reset Key, Learn Key.
- Persisted learned key data immediately so application rebuilds do not require relearning.
- Added stable consumer-event matching for Rii i25 mute/volume-style HID events.
- Removed the modal delete confirmation so deletion does not pause the slideshow; Trash remains the default destination.
- Added duplicate-delete protection during repeated remote events.

- Added a large opposite-corner clock/date OSD with `HH:mm` and uppercase `EEE d MMM` formatting.
- Replaced the interval slider with a validated seconds input field.
- Persisted learned secondary-key data as one settings record and restored it on launch.
- Fixed folder-path persistence so unrelated settings saves cannot erase the selected folder.
- Settings reload from UserDefaults on application start.

### Linux planning

- Documented the Debian-based Linux port plan in `README.md`.
- Defined the proposed shared core, Qt 6 UI, XDG paths, Trash behavior, Debian packaging, and X11/Wayland acceptance gates.
- Added the first Qt 6 Linux slideshow slice with CMake and a version-validated Debian package pipeline.
- Linux support is still not a release; settings, deletion, metadata/OSD, startup integration, and Ansible deployment remain.

## Development process

Changes are developed against the working macOS bundle, compiled with the available SDK, installed into `/Applications`, code-signed ad hoc for local execution, and verified by checking the resulting process and bundle. Documentation is updated alongside user-visible behavior. Linux work will begin by extracting platform-independent indexing, metadata, settings, and deletion behavior before implementing a Debian-native UI and package.
### Rotation controls

- Added persistent photo rotation: Up Arrow rotates clockwise and Down Arrow rotates anti-clockwise.
- Rotations are written back to the original image file using an atomic temporary-file replacement.
