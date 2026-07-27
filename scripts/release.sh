#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
application_name="Mac Display Connect"
release_branch=main
notary_profile=${MAC_DISPLAY_CONNECT_NOTARY_PROFILE:-xdigest-notary}
temporary_directory=$(mktemp -d)
application_directory="$temporary_directory/$application_name.app"
dmg_path="$temporary_directory/MacDisplayConnect.dmg"
mounted_volume=

cleanup() {
    if [[ -n "$mounted_volume" ]]; then
        hdiutil detach "$mounted_volume" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

log() {
    print "==> $*"
}

die() {
    print -u2 "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

github_api() {
    gh api --hostname "$repository_host" "$@"
}

release_state() {
    gh release list --repo "$repository_selector" \
        --limit 100 --json tagName,isDraft \
        --jq ".[] | select(.tagName == \"$tag\") | .isDraft"
}

read_release_snapshot() {
    local snapshot

    snapshot=$(
        github_api "repos/$repository/releases/$release_id" \
            --jq '
                ([.assets[]
                    | select(.name == "MacDisplayConnect.dmg")]) as $assets
                | [
                    .id,
                    .draft,
                    .tag_name,
                    ($assets | length),
                    (.assets | length),
                    ($assets[0].id // 0),
                    ($assets[0].digest // "-"),
                    ($assets[0].state // "-"),
                    ($assets[0].size // 0)
                ]
                | @tsv
            '
    ) || die "Could not inspect GitHub release $tag."

    IFS=$'\t' read -r \
        snapshot_release_id \
        snapshot_is_draft \
        snapshot_tag \
        asset_count \
        total_asset_count \
        remote_asset_id \
        remote_asset_digest \
        remote_asset_state \
        remote_asset_size <<< "$snapshot"
}

remote_tag_target() {
    git ls-remote --tags origin \
        "refs/tags/$tag" "refs/tags/$tag^{}" |
        awk 'END { print $1 }'
}

notarize() {
    local artifact=$1
    local output

    output=$(
        xcrun notarytool submit "$artifact" \
            --keychain-profile "$notary_profile" \
            --wait 2>&1
    ) || {
        print -u2 "$output"
        die "Notarization failed for ${artifact:t}."
    }
    print "$output"
    [[ "$output" == *"status: Accepted"* ]] \
        || die "Notarization was not accepted for ${artifact:t}."
}

validate_uploaded_dmg() {
    local download_directory="$temporary_directory/uploaded-asset"
    local downloaded_dmg="$download_directory/MacDisplayConnect.dmg"
    local mount_point="$temporary_directory/existing-volume"
    local downloaded_app="$mount_point/$application_name.app"
    local downloaded_digest
    local downloaded_code_hash
    local downloaded_team
    local expected_code_hash
    local expected_team

    mkdir -p "$download_directory" "$mount_point"
    gh release download "$tag" \
        --repo "$repository_selector" \
        --pattern MacDisplayConnect.dmg \
        --dir "$download_directory" \
        --clobber \
        || die "Could not download the uploaded DMG."

    downloaded_digest="sha256:$(
        shasum -a 256 "$downloaded_dmg" |
            awk '{ print $1 }'
    )"
    [[ "$downloaded_digest" == "$validated_asset_digest" ]] \
        || die "The downloaded DMG checksum is incorrect."

    codesign --verify --strict --verbose=2 "$downloaded_dmg"
    hdiutil verify "$downloaded_dmg"
    xcrun stapler validate "$downloaded_dmg"
    spctl --assess --type open --context context:primary-signature \
        --verbose=2 "$downloaded_dmg"

    mounted_volume=$mount_point
    hdiutil attach "$downloaded_dmg" \
        -readonly \
        -nobrowse \
        -mountpoint "$mount_point"

    [[ -d "$downloaded_app" && ! -L "$downloaded_app" ]] \
        || die "The uploaded DMG does not contain $application_name.app."
    [[ -L "$mount_point/Applications" \
        && "$(readlink "$mount_point/Applications")" == /Applications ]] \
        || die "The uploaded DMG does not contain the Applications shortcut."
    [[ -f "$mount_point/.DS_Store" \
        && ! -L "$mount_point/.DS_Store" ]] \
        || die "The uploaded DMG does not contain its Finder layout."
    [[ -f "$mount_point/.background/dmg-background.tiff" \
        && ! -L "$mount_point/.background/dmg-background.tiff" ]] \
        || die "The uploaded DMG does not contain its background."
    [[ -f "$mount_point/.VolumeIcon.icns" \
        && ! -L "$mount_point/.VolumeIcon.icns" ]] \
        || die "The uploaded DMG does not contain its volume icon."

    codesign --verify --deep --strict --verbose=2 "$downloaded_app"
    xcrun stapler validate "$downloaded_app"
    spctl --assess --type execute --verbose=2 "$downloaded_app"
    [[ "$(
        plutil -extract CFBundleShortVersionString raw -o - \
            "$downloaded_app/Contents/Info.plist"
    )" == "$version" ]] || die "The uploaded DMG contains the wrong app version."
    [[ "$(
        plutil -extract CFBundleVersion raw -o - \
            "$downloaded_app/Contents/Info.plist"
    )" == "$build_number" ]] || die "The uploaded DMG contains the wrong app build."

    expected_team=$(
        codesign -dvv "$application_directory" 2>&1 |
            sed -n 's/^TeamIdentifier=//p'
    )
    downloaded_team=$(
        codesign -dvv "$downloaded_app" 2>&1 |
            sed -n 's/^TeamIdentifier=//p'
    )
    [[ -n "$expected_team" && "$downloaded_team" == "$expected_team" ]] \
        || die "The uploaded DMG was signed by the wrong developer team."

    expected_code_hash=$(
        codesign -dvvv "$application_directory" 2>&1 |
            sed -n 's/^CDHash=//p'
    )
    downloaded_code_hash=$(
        codesign -dvvv "$downloaded_app" 2>&1 |
            sed -n 's/^CDHash=//p'
    )
    [[ -n "$expected_code_hash" \
        && "$downloaded_code_hash" == "$expected_code_hash" ]] \
        || die "The uploaded DMG does not contain the current release build."

    hdiutil detach "$mounted_volume"
    mounted_volume=
}

version=${1:-}
[[ $# == 1 && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Usage: ./scripts/release.sh VERSION (for example, 1.0.0)"

tag="v$version"

cd "$project_directory"
build_number=$(git rev-list --count HEAD)

log "Preflight"
for command_name in swift git gh security xcrun ditto hdiutil codesign \
    xattr spctl plutil shasum readlink create-dmg gm convert
do
    require_command "$command_name"
done

create_dmg_version=$(create-dmg --version)
[[ "$create_dmg_version" == 7.1.0 ]] \
    || die "create-dmg 7.1.0 is required; found $create_dmg_version."

[[ "$(git branch --show-current)" == "$release_branch" ]] \
    || die "Releases must run from $release_branch."
[[ -z "$(git status --porcelain)" ]] \
    || die "The working tree is not clean. Commit or stash changes first."

gh auth status >/dev/null 2>&1 \
    || die "GitHub CLI is not authenticated. Run: gh auth login"

origin_url=$(git remote get-url origin) \
    || die "The origin remote is unavailable."
repository=$(
    gh repo view "$origin_url" --json nameWithOwner --jq .nameWithOwner
) || die "Could not resolve the GitHub repository from origin."
repository_url=$(
    gh repo view "$origin_url" --json url --jq .url
) || die "Could not resolve the GitHub repository URL from origin."
[[ -n "$repository" && -n "$repository_url" ]] \
    || die "Could not resolve the GitHub repository from origin."
repository_host=${repository_url#*://}
repository_host=${repository_host%%/*}
repository_selector="$repository_host/$repository"
[[ -n "$repository_host" ]] \
    || die "Could not resolve the GitHub host from origin."

signing_identity=${CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(
        security find-identity -v -p codesigning 2>/dev/null |
            sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
            head -n 1
    )
fi
[[ -n "$signing_identity" ]] \
    || die "No Developer ID Application signing identity was found."

xcrun notarytool history \
    --keychain-profile "$notary_profile" >/dev/null 2>&1 \
    || die "Notary profile '$notary_profile' is unavailable."

git fetch origin "$release_branch"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$release_branch")" ]] \
    || die "Local $release_branch must exactly match origin/$release_branch."
release_commit=$(git rev-parse HEAD)

existing_release_state=$(release_state) || true
if [[ "$existing_release_state" == false ]]; then
    die "GitHub release $tag already exists."
fi

if git show-ref --verify --quiet "refs/tags/$tag"; then
    local_tag_commit=$(git rev-list -n 1 "$tag")
    [[ "$local_tag_commit" == "$release_commit" ]] \
        || die "Tag $tag already exists locally at a different commit."
fi
remote_tag_commit=$(remote_tag_target) \
    || die "Could not check tags on origin."
if [[ -n "$remote_tag_commit" ]]; then
    [[ "$remote_tag_commit" == "$release_commit" ]] \
        || die "Tag $tag already exists on origin at a different commit."
fi

log "Running tests"
swift test --jobs 1

log "Building $application_name $version ($build_number)"
BUILD_CONFIGURATION=release \
APP_VERSION="$version" \
APP_BUILD="$build_number" \
REQUIRE_DEVELOPER_ID=1 \
CODESIGN_IDENTITY="$signing_identity" \
APP_OUTPUT_PATH="$application_directory" \
    "$script_directory/build-app.sh"

[[ -d "$application_directory" ]] \
    || die "The build did not produce $application_directory."

log "Verifying app"
xattr -cr "$application_directory"
codesign --force --options runtime --timestamp \
    --sign "$signing_identity" "$application_directory"
codesign --verify --deep --strict --verbose=2 "$application_directory"
[[ "$(
    plutil -extract CFBundleShortVersionString raw -o - \
        "$application_directory/Contents/Info.plist"
)" == "$version" ]] || die "The app version is incorrect."
[[ "$(
    plutil -extract CFBundleVersion raw -o - \
        "$application_directory/Contents/Info.plist"
)" == "$build_number" ]] || die "The app build number is incorrect."

app_zip="$temporary_directory/MacDisplayConnect.zip"
log "Notarizing app"
ditto -c -k --keepParent "$application_directory" "$app_zip"
notarize "$app_zip"
xcrun stapler staple "$application_directory"
xcrun stapler validate "$application_directory"
spctl --assess --type execute --verbose=2 "$application_directory"

log "Creating DMG"
APP_INPUT_PATH="$application_directory" \
DMG_OUTPUT_PATH="$dmg_path" \
    "$project_directory/make-dmg.sh" --no-build --no-open

xattr -cr "$dmg_path"
codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
hdiutil verify "$dmg_path"

log "Notarizing DMG"
notarize "$dmg_path"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature \
    --verbose=2 "$dmg_path"

log "Rechecking $release_branch"
[[ -z "$(git status --porcelain)" ]] \
    || die "The working tree changed during the release."
[[ "$(git rev-parse HEAD)" == "$release_commit" ]] \
    || die "HEAD changed during the release."
git fetch origin "$release_branch"
[[ "$(git rev-parse "origin/$release_branch")" == "$release_commit" ]] \
    || die "origin/$release_branch changed during the release. Update and try again."

log "Ensuring tag $tag"
if ! git show-ref --verify --quiet "refs/tags/$tag"; then
    git tag -a "$tag" -m "$application_name $version"
fi

remote_tag_commit=$(remote_tag_target) \
    || die "Could not recheck tag $tag on origin."
if [[ -z "$remote_tag_commit" ]]; then
    git push origin "$tag" || die "Could not push $tag."
    remote_tag_commit=$(remote_tag_target) \
        || die "Could not verify pushed tag $tag."
fi
[[ "$remote_tag_commit" == "$release_commit" ]] \
    || die "Remote tag $tag does not point to the released commit."

current_release_state=$(release_state) || true
if [[ "$current_release_state" == false ]]; then
    die "GitHub release $tag became public during the release."
elif [[ -z "$current_release_state" ]]; then
    gh release create "$tag" \
        --repo "$repository_selector" \
        --title "$application_name $version" \
        --generate-notes \
        --verify-tag \
        --draft \
        || die "Draft release creation failed. No public release was created."
fi

[[ "$(release_state)" == true ]] \
    || die "GitHub release $tag is not a draft."

local_asset_digest="sha256:$(
    shasum -a 256 "$dmg_path" |
        awk '{ print $1 }'
)"

release_id=$(
    github_api "repos/$repository/releases/tags/$tag" --jq .id
) || die "Could not resolve draft release $tag."
read_release_snapshot
[[ "$snapshot_release_id" == "$release_id" \
    && "$snapshot_is_draft" == true \
    && "$snapshot_tag" == "$tag" ]] \
    || die "GitHub release $tag changed before upload."

case "$asset_count" in
    0)
        [[ "$total_asset_count" == 0 ]] \
            || die "Draft release $tag contains unexpected assets."
        log "Uploading current DMG to draft release $tag"
        upload_url=$(
            github_api "repos/$repository/releases/$release_id" \
                --jq "select(.draft == true and .tag_name == \"$tag\")
                    | .upload_url
                    | sub(\"\\\\{.*$\"; \"\")"
        ) || die "Could not resolve the upload URL for $tag."
        [[ -n "$upload_url" ]] \
            || die "GitHub release $tag is no longer a draft."
        gh api --method POST \
            --header "Content-Type: application/octet-stream" \
            --input "$dmg_path" \
            "$upload_url?name=MacDisplayConnect.dmg" >/dev/null \
            || die "Could not upload the DMG to draft release $tag."

        read_release_snapshot
        [[ "$snapshot_release_id" == "$release_id" \
            && "$snapshot_is_draft" == true \
            && "$snapshot_tag" == "$tag" \
            && "$asset_count" == 1 \
            && "$total_asset_count" == 1 \
            && "$remote_asset_state" == uploaded \
            && "$remote_asset_digest" == "$local_asset_digest" \
            && "$remote_asset_size" -gt 0 ]] \
            || die "The draft release does not contain the current DMG."
        ;;
    1)
        [[ "$total_asset_count" == 1 \
            && "$remote_asset_state" == uploaded \
            && "$remote_asset_digest" == sha256:* \
            && "$remote_asset_size" -gt 0 ]] \
            || die "The existing draft DMG is incomplete."
        log "Validating the DMG already attached to draft release $tag"
        ;;
    *)
        die "Draft release $tag contains duplicate MacDisplayConnect.dmg assets."
        ;;
esac

validated_asset_id=$remote_asset_id
validated_asset_digest=$remote_asset_digest

validate_uploaded_dmg

log "Publishing $tag"
[[ -z "$(git status --porcelain)" ]] \
    || die "The working tree changed before publication."
[[ "$(git rev-parse HEAD)" == "$release_commit" ]] \
    || die "HEAD changed before publication."
git fetch origin "$release_branch"
[[ "$(git rev-parse "origin/$release_branch")" == "$release_commit" ]] \
    || die "origin/$release_branch changed before publication."
[[ "$(remote_tag_target)" == "$release_commit" ]] \
    || die "Remote tag $tag changed before publication."
tag_release_id=$(
    github_api "repos/$repository/releases/tags/$tag" --jq .id
) || die "Could not recheck GitHub release $tag."
[[ "$tag_release_id" == "$release_id" ]] \
    || die "GitHub release $tag changed before publication."
[[ "sha256:$(
    shasum -a 256 "$dmg_path" |
        awk '{ print $1 }'
)" == "$local_asset_digest" ]] \
    || die "The local DMG changed before publication."
read_release_snapshot
[[ "$snapshot_release_id" == "$release_id" \
    && "$snapshot_is_draft" == true \
    && "$snapshot_tag" == "$tag" \
    && "$asset_count" == 1 \
    && "$total_asset_count" == 1 \
    && "$remote_asset_id" == "$validated_asset_id" \
    && "$remote_asset_state" == uploaded \
    && "$remote_asset_digest" == "$validated_asset_digest" \
    && "$remote_asset_size" -gt 0 ]] \
    || die "The validated draft release changed before publication."

github_api --method PATCH "repos/$repository/releases/$release_id" \
    -F draft=false >/dev/null \
    || die "The release remains a draft because publishing failed."

published_tag_commit=$(remote_tag_target) \
    || die "Could not verify published tag $tag."
[[ "$published_tag_commit" == "$release_commit" ]] \
    || die "Published tag $tag does not point to the released commit."

read_release_snapshot
[[ "$snapshot_release_id" == "$release_id" \
    && "$snapshot_is_draft" == false \
    && "$snapshot_tag" == "$tag" \
    && "$asset_count" == 1 \
    && "$total_asset_count" == 1 \
    && "$remote_asset_id" == "$validated_asset_id" \
    && "$remote_asset_digest" == "$validated_asset_digest" ]] \
    || die "The published release does not match the validated draft."

log "Released $tag"
print "    $repository_url/releases/tag/$tag"
