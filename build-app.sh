#!/bin/bash
# build-app.sh — assembles FIXLens.app from the SPM release build
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="FIXLens"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}.app"
ICON_SRC="${SCRIPT_DIR}/Sources/FIXLens/Resources/Assets.xcassets/AppIcon.appiconset"

# ── 1. Build release binary ──────────────────────────────────────────────────
echo "Building ${APP_NAME} (release)…"
swift build -c release --arch arm64
BUILD_DIR="${SCRIPT_DIR}/.build/release"

# ── 2. Create bundle skeleton ────────────────────────────────────────────────
echo "Assembling ${APP_NAME}.app…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# ── 3. Copy binary ───────────────────────────────────────────────────────────
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# ── 4. Copy SPM resources bundle ─────────────────────────────────────────────
# Bundle.module looks for FIXLens_FIXLens.bundle next to the executable
# and under Bundle.main.resourceURL — copy both locations so it resolves
# regardless of how the app is launched.
RESOURCES_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RESOURCES_BUNDLE}" ]; then
    cp -R "${RESOURCES_BUNDLE}" "${APP_DIR}/Contents/Resources/"
    # Also symlink next to binary so Bundle.module fallback works
    ln -sf "../Resources/${APP_NAME}_${APP_NAME}.bundle" \
           "${APP_DIR}/Contents/MacOS/${APP_NAME}_${APP_NAME}.bundle"
else
    echo "WARNING: resources bundle not found at ${RESOURCES_BUNDLE}"
fi

# ── 5. Build AppIcon.icns ─────────────────────────────────────────────────────
ICONSET_DIR="/tmp/${APP_NAME}.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

cp "${ICON_SRC}/icon_16x16.png"      "${ICONSET_DIR}/icon_16x16.png"
cp "${ICON_SRC}/icon_16x16@2x.png"  "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${ICON_SRC}/icon_32x32.png"      "${ICONSET_DIR}/icon_32x32.png"
cp "${ICON_SRC}/icon_32x32@2x.png"  "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${ICON_SRC}/icon_128x128.png"    "${ICONSET_DIR}/icon_128x128.png"
cp "${ICON_SRC}/icon_128x128@2x.png" "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${ICON_SRC}/icon_256x256.png"    "${ICONSET_DIR}/icon_256x256.png"
cp "${ICON_SRC}/icon_256x256@2x.png" "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${ICON_SRC}/icon_512x512.png"    "${ICONSET_DIR}/icon_512x512.png"
cp "${ICON_SRC}/icon_512x512@2x.png" "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

# ── 6. Write Info.plist ───────────────────────────────────────────────────────
cat > "${APP_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.openyield.fixlens</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>FIXLens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.3</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# ── 7. Launch ─────────────────────────────────────────────────────────────────
echo ""
echo "✓ ${APP_DIR}"
echo ""
echo "  To run:              open \"${APP_DIR}\""
echo "  To install:          cp -R \"${APP_DIR}\" /Applications/"
echo "  To zip for sharing:  cd \"${SCRIPT_DIR}\" && zip -r FIXLens.zip FIXLens.app"
