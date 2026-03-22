#!/bin/bash

set -e

# Get version from project
VERSION=$(grep -m1 "MARKETING_VERSION" chatmyllm.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
APP_NAME="chatmyllm"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR="build"

echo "Building ${APP_NAME} version ${VERSION}..."

# Clean and build Release to local build directory
xcodebuild -project chatmyllm.xcodeproj \
    -scheme chatmyllm \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    clean build

echo "Creating DMG..."

# Prepare staging directory
STAGING_DIR=$(mktemp -d)
trap "rm -rf ${STAGING_DIR}" EXIT

# Copy app to staging
cp -R "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" "${STAGING_DIR}/"

# Create Applications symlink
ln -s /Applications "${STAGING_DIR}/Applications"

# Remove old DMG if exists
rm -f "${DMG_NAME}"

# Create DMG
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

echo "✓ DMG created: ${DMG_NAME}"
ls -lh "${DMG_NAME}"
