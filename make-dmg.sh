#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h}
application_name="Mac Display Connect"
application_directory=${APP_INPUT_PATH:-"$project_directory/.build/products/$application_name.app"}
dmg_path=${DMG_OUTPUT_PATH:-"$project_directory/dist/MacDisplayConnect.dmg"}
dmg_path=${dmg_path:A}
output_directory=${dmg_path:h}
temporary_directory=$(mktemp -d)
mounted_volume=
build_app=1
open_dmg=1

cleanup() {
    if [[ -n "$mounted_volume" ]]; then
        hdiutil detach "$mounted_volume" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

die() {
    print -u2 "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$2"
}

detach_mounted_copies() {
    local image_info="$temporary_directory/image-info.plist"
    local image_count image_index image_path
    local entity_count entity_index mount_point

    hdiutil info -plist > "$image_info"
    image_count=$(plutil -extract images raw -o - "$image_info")

    for (( image_index = 0; image_index < image_count; image_index++ )); do
        image_path=$(
            plutil -extract "images.$image_index.image-path" raw -o - \
                "$image_info"
        )
        [[ "$image_path" == "$dmg_path" ]] || continue

        entity_count=$(
            plutil -extract "images.$image_index.system-entities" raw -o - \
                "$image_info"
        )
        for (( entity_index = 0;
            entity_index < entity_count;
            entity_index++ )); do
            mount_point=$(
                plutil -extract \
                    "images.$image_index.system-entities.$entity_index.mount-point" \
                    raw -o - "$image_info" 2>/dev/null
            ) || continue
            [[ -n "$mount_point" ]] || continue

            print "Ejecting stale mounted copy at $mount_point"
            hdiutil detach "$mount_point" >/dev/null \
                || die "Close files in $mount_point and try again."
        done
    done
}

usage() {
    print "Usage: ./make-dmg.sh [--no-build] [--no-open]"
}

while (( $# > 0 )); do
    case "$1" in
        --no-build)
            build_app=0
            ;;
        --no-open)
            open_dmg=0
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
    shift
done

require_command create-dmg \
    "create-dmg is required. Install it with: npm install --global create-dmg@7.1.0"
require_command gm \
    "GraphicsMagick is required. Install it with: brew install graphicsmagick"
require_command convert \
    "ImageMagick is required. Install it with: brew install imagemagick"

create_dmg_version=$(create-dmg --version)
[[ "$create_dmg_version" == 7.1.0 ]] \
    || die "create-dmg 7.1.0 is required; found $create_dmg_version."

if [[ "$build_app" == 1 ]]; then
    APP_OUTPUT_PATH="$application_directory" \
    BUILD_CONFIGURATION=release \
        "$project_directory/scripts/build-app.sh"
fi

[[ -d "$application_directory" ]] \
    || {
        print -u2 "Mac app not found at $application_directory"
        exit 1
    }

dmg_source="$temporary_directory/dmg"
temporary_dmg="$temporary_directory/MacDisplayConnect.dmg"
staged_application="$dmg_source/$application_name.app"
generated_dmg="$temporary_directory/$application_name.dmg"
mkdir -p "$dmg_source"
ditto "$application_directory" "$staged_application"
xattr -dr com.apple.FinderInfo "$staged_application" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$staged_application" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$staged_application"
plutil -lint "$staged_application/Contents/Info.plist" >/dev/null

create_dmg_output=
if ! create_dmg_output=$(
    create-dmg \
        --no-code-sign \
        --no-version-in-filename \
        --dmg-title="$application_name" \
        "$staged_application" \
        "$temporary_directory" 2>&1
); then
    print -r -- "$create_dmg_output"
    [[ -f "$generated_dmg" ]] \
        || die "create-dmg did not produce $generated_dmg"
fi
print -r -- "$create_dmg_output"
[[ -f "$generated_dmg" ]] \
    || die "create-dmg did not produce $generated_dmg"
mv "$generated_dmg" "$temporary_dmg"
hdiutil verify "$temporary_dmg"

verification_mount="$temporary_directory/verify"
mkdir -p "$verification_mount"
mounted_volume=$verification_mount
hdiutil attach "$temporary_dmg" \
    -readonly \
    -nobrowse \
    -mountpoint "$verification_mount" >/dev/null

mounted_application="$verification_mount/$application_name.app"
background="$verification_mount/.background/dmg-background.tiff"
[[ -d "$mounted_application" && ! -L "$mounted_application" ]] \
    || die "The DMG does not contain $application_name.app."
[[ -L "$verification_mount/Applications" \
    && "$(readlink "$verification_mount/Applications")" == /Applications ]] \
    || die "The DMG does not contain the Applications shortcut."
[[ -f "$verification_mount/.DS_Store" ]] \
    || die "The DMG does not contain its Finder layout."
[[ -f "$background" ]] \
    || die "The DMG does not contain its background."
[[ -f "$verification_mount/.VolumeIcon.icns" ]] \
    || die "The DMG does not contain its volume icon."
[[ "$(sips -g pixelWidth "$background" |
    awk '/pixelWidth:/ { print $2 }')" == 660 ]] \
    || die "The DMG background has the wrong width."
[[ "$(sips -g pixelHeight "$background" |
    awk '/pixelHeight:/ { print $2 }')" == 400 ]] \
    || die "The DMG background has the wrong height."
codesign --verify --deep --strict --verbose=2 "$mounted_application"

hdiutil detach "$mounted_volume" >/dev/null
mounted_volume=

mkdir -p "$output_directory"
detach_mounted_copies
mv "$temporary_dmg" "$dmg_path"

print "Created $dmg_path"

if [[ "$open_dmg" == 1 ]]; then
    open "$dmg_path"
fi
