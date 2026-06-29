#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
APP_NAME="ClipLAN"
BUNDLE_ID="${BUNDLE_ID:-app.cliplan.ClipLAN}"
MIN_SYSTEM_VERSION="14.0"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ROOT="$(mktemp -d /tmp/cliplan-package.XXXXXX)"
APP_STAGING="$BUILD_ROOT/$APP_NAME.app"
APP_CONTENTS="$APP_STAGING/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
STABLE_APP="$DIST_DIR/$APP_NAME.app"

usage() {
  echo "usage: $0 [app|zip|dmg|pkg|all]" >&2
}

if [[ "$MODE" != "app" && "$MODE" != "zip" && "$MODE" != "dmg" && "$MODE" != "pkg" && "$MODE" != "all" ]]; then
  usage
  exit 2
fi

if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -p codesigning -v | grep -Fq "\"$SIGN_IDENTITY\""; then
  echo "warning: code signing identity not found, falling back to ad-hoc signing: $SIGN_IDENTITY" >&2
  SIGN_IDENTITY="-"
fi

CORE_SOURCES=()
while IFS= read -r source_file; do
  CORE_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/PasteCore" -name '*.swift' | sort)

APP_SOURCES=()
while IFS= read -r source_file; do
  APP_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/Paste" -name '*.swift' | sort)

mkdir -p "$DIST_DIR" "$BUILD_ROOT/universal" "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"

for ARCH in arm64 x86_64; do
  TARGET="${ARCH}-apple-macosx${MIN_SYSTEM_VERSION}"
  ARCH_DIR="$BUILD_ROOT/$ARCH"
  mkdir -p "$ARCH_DIR"

  swiftc \
    -target "$TARGET" \
    -emit-library \
    -emit-module \
    -module-name PasteCore \
    -parse-as-library "${CORE_SOURCES[@]}" \
    -emit-module-path "$ARCH_DIR/PasteCore.swiftmodule" \
    -o "$ARCH_DIR/libPasteCore.dylib" \
    -framework Vision \
    -lsqlite3 \
    -Xlinker -install_name \
    -Xlinker @rpath/libPasteCore.dylib

  swiftc \
    -target "$TARGET" "${APP_SOURCES[@]}" \
    -I "$ARCH_DIR" \
    -L "$ARCH_DIR" \
    -lPasteCore \
    -o "$ARCH_DIR/$APP_NAME" \
    -framework Carbon \
    -framework ApplicationServices \
    -framework QuickLookThumbnailing \
    -framework ServiceManagement \
    -framework Vision \
    -Xlinker -rpath \
    -Xlinker @executable_path/../Frameworks
done

lipo -create "$BUILD_ROOT/arm64/$APP_NAME" "$BUILD_ROOT/x86_64/$APP_NAME" -output "$BUILD_ROOT/universal/$APP_NAME"
lipo -create "$BUILD_ROOT/arm64/libPasteCore.dylib" "$BUILD_ROOT/x86_64/libPasteCore.dylib" -output "$BUILD_ROOT/universal/libPasteCore.dylib"

install -m 755 "$BUILD_ROOT/universal/$APP_NAME" "$APP_MACOS/$APP_NAME"
install -m 755 "$BUILD_ROOT/universal/libPasteCore.dylib" "$APP_FRAMEWORKS/libPasteCore.dylib"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_STAGING"
codesign --force --sign "$SIGN_IDENTITY" "$APP_FRAMEWORKS/libPasteCore.dylib" >/dev/null
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_STAGING" >/dev/null
xattr -cr "$APP_STAGING"
codesign --verify --deep --strict "$APP_STAGING"

COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP_STAGING" "$STABLE_APP"
xattr -cr "$STABLE_APP"
codesign --verify --deep --strict "$STABLE_APP"
echo "app: $STABLE_APP"

if [[ "$MODE" == "zip" || "$MODE" == "all" ]]; then
  COPYFILE_DISABLE=1 ditto -c -k --keepParent "$APP_STAGING" "$DIST_DIR/$APP_NAME.zip"
  xattr -cr "$DIST_DIR/$APP_NAME.zip" 2>/dev/null || true
  echo "zip: $DIST_DIR/$APP_NAME.zip"
fi

if [[ "$MODE" == "dmg" || "$MODE" == "all" ]]; then
  if ! hdiutil create -volname "$APP_NAME" -srcfolder "$APP_STAGING" -ov -format UDZO "$BUILD_ROOT/$APP_NAME.dmg" >/dev/null 2>"$BUILD_ROOT/hdiutil.log"; then
    cat "$BUILD_ROOT/hdiutil.log" >&2
    exit 1
  fi
  install -m 644 "$BUILD_ROOT/$APP_NAME.dmg" "$DIST_DIR/$APP_NAME.dmg"
  xattr -cr "$DIST_DIR/$APP_NAME.dmg" 2>/dev/null || true
  echo "dmg: $DIST_DIR/$APP_NAME.dmg"
fi

if [[ "$MODE" == "pkg" || "$MODE" == "all" ]]; then
  if ! COPYFILE_DISABLE=1 productbuild --component "$APP_STAGING" /Applications "$BUILD_ROOT/$APP_NAME.pkg" >/dev/null 2>"$BUILD_ROOT/productbuild.log"; then
    cat "$BUILD_ROOT/productbuild.log" >&2
    exit 1
  fi
  install -m 644 "$BUILD_ROOT/$APP_NAME.pkg" "$DIST_DIR/$APP_NAME.pkg"
  xattr -cr "$DIST_DIR/$APP_NAME.pkg" 2>/dev/null || true
  echo "pkg: $DIST_DIR/$APP_NAME.pkg"
fi
