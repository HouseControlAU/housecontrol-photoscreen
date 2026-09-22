#!/usr/bin/env bash
set -euo pipefail

source_root="${SOURCE_ROOT:-/src}"
out_dir="${OUT_DIR:-/out}"
build_dir="${BUILD_DIR:-/tmp/housecontrol-photoscreen-build}"

rm -rf "$build_dir"
cmake -S "$source_root/linux" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" --parallel
cpack --config "$build_dir/CPackConfig.cmake" -G DEB --verbose

mkdir -p "$out_dir"
find "$build_dir" -maxdepth 1 -type f -name 'housecontrol-photoscreen_*.deb' -exec cp -f {} "$out_dir/" \;

shopt -s nullglob
packages=("$out_dir"/housecontrol-photoscreen_*.deb)
if (( ${#packages[@]} == 0 )); then
    printf 'No Debian package was produced\n' >&2
    exit 1
fi
printf 'Produced packages:\n'
printf ' - %s\n' "${packages[@]}"
