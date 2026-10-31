#!/usr/bin/env bash
set -euo pipefail

# Builds GotifyDesktop.app for local debug/UI testing (default) or packages
# arm64 + amd64 release DMG installers (`--release`).
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

build_configuration="${BUILD_CONFIGURATION:-debug}"
if [[ "${1:-}" == "--release" ]]; then
  build_configuration="release"
fi

assemble_app_bundle() {
  local bin_path="$1"
  local app_path="$bin_path/GotifyDesktop.app"
  local strip_binary="$2"

  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cp "$bin_path/GotifyDesktop" "$app_path/Contents/MacOS/GotifyDesktop"
  if [[ "$strip_binary" == "true" ]]; then
    strip -x "$app_path/Contents/MacOS/GotifyDesktop"
  fi
  cp "Resources/AppBundle/Info.plist" "$app_path/Contents/Info.plist"

  if [[ -d "Resources/AppBundle/Resources" ]]; then
    cp -R "Resources/AppBundle/Resources/." "$app_path/Contents/Resources/"
  fi

  # The legacy AppKit notification center resolves its custom alert sound from the main App bundle.
  cp "Sources/GotifyDesktop/SharedUI/Sounds/GotifyNotification.caf" "$app_path/Contents/Resources/GotifyNotification.caf"
  # Ship both licenses with binary copies; the project license does not replace third-party terms.
  cp "LICENSE" "$app_path/Contents/Resources/LICENSE"
  cp "THIRD_PARTY_NOTICES.md" "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
  cp -R "$bin_path/GotifyDesktop_GotifyDesktop.bundle" "$app_path/Contents/Resources/GotifyDesktop_GotifyDesktop.bundle"

  # Rebind the finished bundle to its declared identifier with an ad-hoc signature (`-`).
  # Uses no certificate, Apple account, Keychain item, or machine data.
  local bundle_identifier
  bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
  local designated_requirement="designated => identifier \"$bundle_identifier\""
  codesign --force --sign - --identifier "$bundle_identifier" -r="$designated_requirement" --timestamp=none "$app_path"

  printf '%s\n' "$app_path"
}

package_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local staging_dir
  staging_dir="$(dirname "$dmg_path")/dmg-staging-$(basename "$dmg_path" .dmg)"

  rm -rf "$dmg_path" "$staging_dir"
  mkdir -p "$staging_dir"
  cp -R "$app_path" "$staging_dir/GotifyDesktop.app"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create -volname "GotifyDesktop" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path" >&2
  rm -rf "$staging_dir"
}

build_dir="$project_root/build"

if [[ "$build_configuration" == "release" ]]; then
  release_dir="$build_dir/dist"
  mkdir -p "$release_dir"

  # 1. Apple Silicon (arm64)
  swift build --build-path "$build_dir" -c release --triple arm64-apple-macosx12.0 --product GotifyDesktop >&2
  arm64_bin_path="$(swift build --build-path "$build_dir" -c release --triple arm64-apple-macosx12.0 --show-bin-path)"
  arm64_app_path="$(assemble_app_bundle "$arm64_bin_path" "true")"
  arm64_dmg_path="$release_dir/GotifyDesktop-macOS-arm64.dmg"
  package_dmg "$arm64_app_path" "$arm64_dmg_path"

  # 2. Intel (amd64 / x86_64)
  swift build --build-path "$build_dir" -c release --triple x86_64-apple-macosx12.0 --product GotifyDesktop >&2
  amd64_bin_path="$(swift build --build-path "$build_dir" -c release --triple x86_64-apple-macosx12.0 --show-bin-path)"
  amd64_app_path="$(assemble_app_bundle "$amd64_bin_path" "true")"
  amd64_dmg_path="$release_dir/GotifyDesktop-macOS-amd64.dmg"
  package_dmg "$amd64_app_path" "$amd64_dmg_path"

  {
    printf '\nRelease DMG packages:\n'
    shasum -a 256 "$arm64_dmg_path" "$amd64_dmg_path"
  } >&2

  printf '%s\n' "$release_dir"
else
  swift build --build-path "$build_dir" -c "$build_configuration" --product GotifyDesktop >&2
  bin_path="$(swift build --build-path "$build_dir" -c "$build_configuration" --show-bin-path)"
  assemble_app_bundle "$bin_path" "false"
fi
