#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
brand_dir="$root/assets/branding"
mac_dir="$root/macos/Runner/Assets.xcassets/AppIcon.appiconset"
android_res="$root/android/app/src/main/res"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to regenerate Fourier icons." >&2
  exit 1
fi

render() {
  local source="$1"
  local size="$2"
  local destination="$3"
  (
    cd "$brand_dir"
    rsvg-convert -w "$size" -h "$size" -o "$destination" "$source"
  )
}

for size in 16 32 64 128 256 512 1024; do
  render "fourier-macos.svg" "$size" "$mac_dir/app_icon_${size}.png"
done

render "fourier-android-legacy.svg" 48 "$android_res/mipmap-mdpi/ic_launcher.png"
render "fourier-android-legacy.svg" 72 "$android_res/mipmap-hdpi/ic_launcher.png"
render "fourier-android-legacy.svg" 96 "$android_res/mipmap-xhdpi/ic_launcher.png"
render "fourier-android-legacy.svg" 144 "$android_res/mipmap-xxhdpi/ic_launcher.png"
render "fourier-android-legacy.svg" 192 "$android_res/mipmap-xxxhdpi/ic_launcher.png"

mkdir -p "$android_res/drawable-nodpi"
render "fourier-android-foreground.svg" 432 \
  "$android_res/drawable-nodpi/ic_launcher_foreground.png"
render "fourier.svg" 1024 "$root/assets/icon.png"
