# HouseControl PhotoScreen

`housecontrol-photoscreen` is a HouseControl photo slideshow for macOS, with a planned Debian-based Linux port.

## macOS features

- Menu-bar utility represented by the HouseControl application icon rather than a text label.
- Background indexing at application start and after a folder change.
- Fullscreen slideshow on the selected display.
- Configurable interval entered as seconds from 5 seconds to 1 hour.
- Sequential or shuffled playback.
- Fade, slide, zoom, Ken Burns, or no transition.
- Double-click anywhere in the slideshow to exit.
- Left/right navigation keys.
- Up Arrow rotates the current photo clockwise; Down Arrow rotates it anti-clockwise and writes the rotated pixels back to the original file.
- On-screen display in any screen corner.
- OSD fields:
  - EXIF date taken
  - Reverse-geocoded city or suburb, state, and country
  - Containing folder name
- Optional large clock and date OSD in the corner opposite the metadata OSD, formatted as `HH:mm` and `EEE d MMM` (for example, `20:00` and `SUN 20 SEP`).
- EXIF and geocoded location cache at `~/Library/Caches/HouseControl PhotoScreen/exif-cache.json`.
- Primary Delete and Forward Delete keyboard actions.
- Optional learned secondary delete key, including Rii i25 keyboard, volume/system, and mouse-button events.
- One-button secondary-key cycle: `Learn Key → Reset Key → Learn Key`; the learned configuration is stored as a single persistent settings record.
- Deleted files move to Trash by default; permanent deletion is an explicit option.
- Deletion runs off the UI thread and displays the deleted filename and full path in the OSD.
- Settings save immediately and reload on startup, including animation, login startup, idle-start delay, and learned-key settings.
- Optional idle-start delay for launching the fullscreen slideshow after inactivity; `0` disables it.
- Settings window includes Start PhotoScreen and Quit actions.
- Application icon is included in the app bundle and used by the menu-bar item.

## Build and package on macOS

The current host uses Command Line Tools and builds directly with Swift and the macOS SDK:

```bash
swiftc -parse-as-library \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  -framework AppKit \
  -framework SwiftUI \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -framework ServiceManagement \
  -framework CoreLocation \
  Sources/HouseControlPhotoScreen/main.swift \
  -o housecontrol-photoscreen
```

The macOS bundle should contain:

```text
HouseControl PhotoScreen.app/
  Contents/
    Info.plist
    MacOS/housecontrol-photoscreen
    Resources/HouseControlPhotoScreen.icns
```

The SwiftPM product is also named `housecontrol-photoscreen`.

## Debian-based Linux port status

Linux support is planned but not yet implemented. The target is Debian 12/13 and compatible Ubuntu/Debian-based systems. The current Swift source is macOS-specific and is not a Linux implementation. See [`linux/README.md`](linux/README.md) for the verified toolchain limitation and port requirements.

### Proposed architecture

1. Extract platform-independent behavior into a shared core:
   - folder indexing and supported-image filtering
   - ordering, shuffle, interval, and cache model
   - EXIF extraction and location-cache schema
   - deletion policy and Trash/permanent-delete decisions
2. Build a native Linux UI using Qt 6 Widgets:
   - fullscreen multi-display window
   - system tray icon and menu
   - settings window
   - keyboard and mouse event handling
3. Use Linux-native services:
   - `inotify` or `fanotify` only when live indexing is added
   - XDG Trash specification for safe deletion
   - XDG desktop entry and application icon
   - XDG config/cache directories
4. Package for Debian:
   - `housecontrol-photoscreen` executable
   - `/usr/share/applications/housecontrol-photoscreen.desktop`
   - `/usr/share/icons/hicolor/*/apps/housecontrol-photoscreen.png`
   - `/usr/share/housecontrol-photoscreen/` for application resources
   - `.deb` package for Debian 12/13 and Ubuntu LTS
5. Verify on X11 and Wayland separately. Fullscreen, tray behavior, global media-key access, and login startup differ between the two session types.

### Linux decisions still required

- Qt 6 versus GTK4/libadwaita implementation.
- X11/Wayland input strategy for learned media and remote keys.
- Whether geocoding is optional, offline, or provided by a HouseControl service.
- Supported image formats and HEIF/WebP codec dependencies.
- Whether login startup uses a desktop autostart entry or a systemd user service.

### Linux acceptance gates

Linux support will not be called complete until the application has been built and exercised on a real Debian-based system with fullscreen display selection, settings persistence, safe Trash deletion, icon/tray behavior, and a reproducible `.deb` artifact.

## Development process

1. Inspect the existing source and live behavior before changing platform code.
2. Keep indexing, metadata, deletion, and settings persistence separate from window presentation where practical.
3. Make one behavior change at a time and compile the real packaged application after each change.
4. Test the installed bundle, not only the raw executable.
5. Treat deletion and permanent deletion as separate paths; default to Trash.
6. Verify external effects such as file deletion and settings persistence by reading the resulting state.
7. Keep macOS-specific APIs behind a platform layer before beginning the Linux port.
8. Record user-visible features, portability decisions, and known limitations in `CHANGELOG.md` and this README.

## Safety and known limitations

- Permanent deletion is not recommended during initial testing.
- macOS login-item registration requires a properly packaged signed application; the local build is ad-hoc signed.
- `CLGeocoder` currently emits a macOS 26 deprecation warning; the Linux port should use an explicit geocoding abstraction.
- There is no periodic folder rescan. The index is refreshed at launch, when the folder changes, and when a photo is deleted from the active slideshow.
