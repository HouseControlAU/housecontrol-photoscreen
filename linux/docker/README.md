# Debian package builder

This container produces the Linux `.deb` package without requiring Qt or Debian tooling on the host.

## Build the image

From the repository root:

```bash
docker build \
  -f linux/docker/Dockerfile \
  -t housecontrol-photoscreen-builder .
```

## Build the package

```bash
mkdir -p linux/dist

docker run --rm \
  -v "$PWD:/src:ro" \
  -v "$PWD/linux/dist:/out" \
  housecontrol-photoscreen-builder
```

The package is written to:

```text
linux/dist/housecontrol-photoscreen_<version>_amd64.deb
```

The version is read from the repository `VERSION.md` through CMake.

## Notes

- Base image: Debian 12 Bookworm.
- Qt 6, CMake, C++ build tools, and `dpkg-dev` are installed in the image.
- Source is mounted read-only; only `linux/dist/` is written on the host.
- Docker Desktop is required on macOS or Windows.
- The GitHub release workflow performs the equivalent build on Ubuntu and uploads the resulting `.deb` to tagged releases.
