# Linux port status

The Linux implementation is **not yet compiled or complete**.

The current source in `Sources/HouseControlPhotoScreen/main.swift` is macOS-specific and imports AppKit, SwiftUI, ServiceManagement, and CoreLocation. It cannot be compiled as a Linux executable without a separate Linux implementation.

## Intended Linux layout

```text
linux/
  README.md              # Linux build and packaging status
  src/                   # Future Qt 6 implementation
  packaging/
    housecontrol-photoscreen.desktop
    debian/
```

## Required Debian build environment

- Debian 12 or 13 / compatible Ubuntu LTS
- CMake 3.24 or newer
- Qt 6 Widgets, Gui, and Multimedia development packages
- C++17 compiler
- Exiv2 or equivalent EXIF library
- XDG desktop and Trash support
- X11 and Wayland test sessions

## Current verified result

On the macOS development host, a Linux Swift target probe fails before compilation because the installed Apple Swift toolchain does not include the Linux linker/toolchain:

```text
error: unableToFind(tool: "swift-autolink-extract")
```

No Linux binary or `.deb` is being claimed until the port is implemented and built on Debian.
