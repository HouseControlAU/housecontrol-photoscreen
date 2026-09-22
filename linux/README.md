# Linux PhotoScreen port

The Linux implementation has its first buildable Qt 6 slice. It is separate from the macOS Swift application and targets Debian-based HouseControl devices.

## Current verified features

- Qt 6 Widgets application built with CMake and C++17.
- Recursive indexing of supported photo files:
  `jpg`, `jpeg`, `png`, `heic`, `heif`, `webp`, `tif`, and `tiff`.
- Fullscreen photo display.
- `Escape` exits.
- Right Arrow or Space advances.
- Left Arrow goes back.
- Configurable interval with a five-second minimum.
- Optional shuffled order.
- Center-locked ratio-based zoom:
  - The complete image starts fitted without stretching.
  - Images whose ratio differs from the display zoom until the display is filled.
  - The image center remains fixed during scaling.
  - Matching-ratio images do not receive unnecessary zoom.
- Desktop entry installed by CMake.
- Debian package generation configured with CPack and executed by Ubuntu GitHub Actions.

## Build

Required packages on Debian 12/13 or compatible Ubuntu:

```bash
sudo apt install build-essential cmake qt6-base-dev
```

Build from this directory:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

Run:

```bash
./build/housecontrol-photoscreen \
  --folder "$HOME/Pictures" \
  --interval 60 \
  --shuffle
```

Options:

```text
--folder PATH       Recursive photo folder; defaults to ~/Pictures
--interval SECONDS  Seconds between photos; minimum 5, default 60
--shuffle           Shuffle indexed photos
--version           Print the application version
```

## Verified on the macOS development host

Homebrew Qt 6.11.2 and CMake 4.4.3 were used to configure and compile the target with Apple Clang. The executable passed `--version` and `--help` checks. An offscreen runtime test indexed a real photo directory and remained in the event loop; an empty directory correctly returned exit code 1.

This is not yet a Debian/Linux release. It still needs Linux-host verification, settings UI, safe deletion, metadata/OSD, update checking, startup integration, packaging, and Ansible deployment before a Linux release is published.

The macOS development host can compile and smoke-test the Qt target, but it cannot generate a `.deb`; CPack's DEB generator is only available on the Linux release runner.
