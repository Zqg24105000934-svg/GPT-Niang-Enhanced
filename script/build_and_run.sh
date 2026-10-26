#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---build-only}"
case "$MODE" in --build-only) ;; *) echo "Usage: bash script/build_and_run.sh --build-only" >&2; exit 2 ;; esac
APP_NAME="GPTNiangEnhanced"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
TASK_CACHE="${GPT_NIANG_BUILD_CACHE:-$ROOT_DIR/macos/.build-cache}"
ASSETS="${GPT_NIANG_ASSETS:-$ROOT_DIR/gpt-niang-usage/assets}"
mkdir -p "$TASK_CACHE/clang" "$TASK_CACHE/swiftpm"
export CLANG_MODULE_CACHE_PATH="$TASK_CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_CACHE/clang"
BUILD_ARGS=(--package-path "$ROOT_DIR/macos" --disable-sandbox --cache-path "$TASK_CACHE/swiftpm" --configuration "${GPT_NIANG_BUILD_CONFIGURATION:-release}")
if [ "${GPT_NIANG_BUILD_UNIVERSAL:-0}" = 1 ]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
if [ -n "${GPT_NIANG_SDK:-}" ]; then BUILD_ARGS+=(--sdk "$GPT_NIANG_SDK"); fi
VERSION="$(node -p "require(process.argv[1]).version" "$ROOT_DIR/gpt-niang-usage/package.json")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid version" >&2; exit 1; fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
# Rebuild only this script's generated bundle; never alter an installed app.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Helpers" "$APP_BUNDLE/Contents/Resources/Backend/runtime" "$APP_BUNDLE/Contents/Resources/Backend/.codex-plugin"
cp "$BIN_DIR/GPTNiangMac" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$BIN_DIR/GPTNiangMac_GPTNiangCore.bundle" "$APP_BUNDLE/Contents/Resources/"
cp "$BIN_DIR/GPTNiangUpdater" "$APP_BUNDLE/Contents/Helpers/GPTNiangUpdater"
for runtime in "$ROOT_DIR/gpt-niang-usage/runtime/"*.mjs; do
  if [ "$(basename "$runtime")" != update.mjs ]; then cp "$runtime" "$APP_BUNDLE/Contents/Resources/Backend/runtime/"; fi
done
cp "$ROOT_DIR/gpt-niang-usage/.codex-plugin/plugin.json" "$APP_BUNDLE/Contents/Resources/Backend/.codex-plugin/"
cp "$ROOT_DIR/gpt-niang-usage/assets/quotes.json" "$APP_BUNDLE/Contents/Resources/"
for asset in gpt-dragon-niang-bust.png gpt-dragon-niang-fullbody.png gpt-dragon-niang-winged-v2.png pet-rig-winged-v1.png pet-rig-chibi-v1.png pet-rig-chibi-dress-v1.png press.wav release.wav; do
  if [ -f "$ASSETS/$asset" ] && [ ! -L "$ASSETS/$asset" ]; then cp "$ASSETS/$asset" "$APP_BUNDLE/Contents/Resources/"; fi
done
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/NOTICE.md" "$ROOT_DIR/docs/ASSETS.md" "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/gpt-niang-usage/assets/quotes-LICENSE.txt" "$ROOT_DIR/gpt-niang-usage/assets/CHARACTER-NOTICE.txt" "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/gpt-niang-usage/assets/ASSET-LICENSE.md" "$ROOT_DIR/gpt-niang-usage/assets/GENERATED-ASSETS.md" "$APP_BUNDLE/Contents/Resources/"
PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string local.gptniang.enhanced "$PLIST"
/usr/bin/plutil -insert CFBundleName -string 'GPT 娘增强版' "$PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string 'GPT 娘增强版' "$PLIST"
/usr/bin/plutil -insert GPTNiangEnhanced -bool YES "$PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "$VERSION.5" "$PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$PLIST"
/usr/bin/plutil -insert LSUIElement -bool YES "$PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$PLIST"
/usr/bin/plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
/usr/bin/xattr -rd com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/xattr -rd com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/GPTNiangUpdater"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
echo "Built $APP_BUNDLE (character artwork uses separate non-commercial terms)."
