#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
products_directory="$project_directory/.build/products"
application_directory="$products_directory/Mac Display Connect.app"
staging_directory=$(mktemp -d)
staging_application="$staging_directory/Mac Display Connect.app"
contents_directory="$staging_application/Contents"
executable_directory="$contents_directory/MacOS"
resources_directory="$contents_directory/Resources"
icon_source="$project_directory/Design/AppIcons/MacDisplayConnect-Mac-1024-v6.png"
iconset_directory="$staging_directory/MacDisplayConnect.iconset"
signing_identity=$(
    security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
        head -n 1
)

swift build --package-path "$project_directory" --jobs 1 \
    -c debug --product MacDisplayConnect

mkdir -p "$products_directory"
mkdir -p "$executable_directory"
mkdir -p "$resources_directory"
cp "$project_directory/.build/debug/MacDisplayConnect" \
    "$executable_directory/MacDisplayConnect"

mkdir -p "$iconset_directory"
sips -z 16 16 "$icon_source" --out "$iconset_directory/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_directory/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_directory/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset_directory/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset_directory/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_directory/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_directory/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_directory/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_directory/icon_512x512.png" >/dev/null
cp "$icon_source" "$iconset_directory/icon_512x512@2x.png"
iconutil -c icns "$iconset_directory" \
    -o "$resources_directory/MacDisplayConnect.icns"

plutil -create xml1 "$contents_directory/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en \
    "$contents_directory/Info.plist"
plutil -insert CFBundleDisplayName -string "Mac Display Connect" \
    "$contents_directory/Info.plist"
plutil -insert CFBundleExecutable -string MacDisplayConnect \
    "$contents_directory/Info.plist"
plutil -insert CFBundleIdentifier -string "local.macdisplayconnect.app" \
    "$contents_directory/Info.plist"
plutil -insert CFBundleIconFile -string "MacDisplayConnect.icns" \
    "$contents_directory/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" \
    "$contents_directory/Info.plist"
plutil -insert CFBundleName -string "Mac Display Connect" \
    "$contents_directory/Info.plist"
plutil -insert CFBundlePackageType -string APPL \
    "$contents_directory/Info.plist"
plutil -insert CFBundleShortVersionString -string "1.0" \
    "$contents_directory/Info.plist"
plutil -insert CFBundleVersion -string "4" \
    "$contents_directory/Info.plist"
plutil -insert LSMinimumSystemVersion -string "26.0" \
    "$contents_directory/Info.plist"
plutil -insert NSBonjourServices -array \
    "$contents_directory/Info.plist"
plutil -insert NSBonjourServices.0 -string "_macdisplayconnect._tcp" \
    "$contents_directory/Info.plist"
plutil -insert NSLocalNetworkUsageDescription \
    -string "Lets Apple Vision Pro request Mac Virtual Display from this Mac." \
    "$contents_directory/Info.plist"

xattr -cr "$staging_application"
codesign --force --options runtime \
    --sign "${signing_identity:--}" \
    "$staging_application"

if [[ -e "$application_directory" ]]; then
    mv "$application_directory" "$staging_directory/previous-application"
fi
mv "$staging_application" "$application_directory"
xattr -cr "$application_directory"

echo "$application_directory"
