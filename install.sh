#!/bin/bash

# Secure Terminal installer for Klik PRO.
#
# This script deliberately is not intended for `curl | bash`. Download it, inspect it,
# then run it. It authenticates the release checksum with a dedicated Ed25519 key
# before it removes quarantine or writes anything into /Applications.

set -euo pipefail

readonly REPOSITORY="AminudinMurad/klik-pro"
readonly RELEASE_PRINCIPAL="klik-pro-release"
readonly RELEASE_NAMESPACE="klik-pro-release"
readonly RELEASE_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRinZxINTO5M8kTyrRXphibZXsiGSj/Q0dIjegq8qXd"
readonly RELEASE_KEY_FINGERPRINT="SHA256:Evg4ITqpPJY/aIT48Zv9Cp3psQfo977uCz/35a2k79E"
readonly EXPECTED_APP_IDENTIFIER="local.klik-pro"
readonly EXPECTED_HELPER_IDENTIFIER="local.klik-pro.helper"

requested_tag="latest"
local_dmg=""
local_checksum=""
local_signature=""
install_directory="/Applications"
verify_only=0
assume_yes=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Downloads, authenticates, verifies, and installs the latest Klik PRO DMG.

Options:
  --version TAG       Install a specific release tag, for example v1.3.9
  --verify-only       Verify the release without installing it
  --yes               Skip the final interactive confirmation
  --install-dir PATH  Install somewhere other than /Applications
  --dmg PATH          Verify/install a local DMG instead of downloading
  --checksum PATH     Local signed SHA-256 manifest used with --dmg
  --signature PATH    Signature for the local checksum manifest
  -h, --help          Show this help

Local verification requires --dmg, --checksum, --signature, and --version.
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '==> %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || fail "--version requires a tag"
            requested_tag="$2"
            shift 2
            ;;
        --verify-only)
            verify_only=1
            shift
            ;;
        --yes)
            assume_yes=1
            shift
            ;;
        --install-dir)
            [[ $# -ge 2 ]] || fail "--install-dir requires a path"
            install_directory="$2"
            shift 2
            ;;
        --dmg)
            [[ $# -ge 2 ]] || fail "--dmg requires a path"
            local_dmg="$2"
            shift 2
            ;;
        --checksum)
            [[ $# -ge 2 ]] || fail "--checksum requires a path"
            local_checksum="$2"
            shift 2
            ;;
        --signature)
            [[ $# -ge 2 ]] || fail "--signature requires a path"
            local_signature="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

for command_name in \
    curl ssh-keygen shasum hdiutil plutil codesign lipo ditto xattr \
    pgrep pkill osascript launchctl open
do
    require_command "$command_name"
done

if [[ -n "$local_dmg" || -n "$local_checksum" || -n "$local_signature" ]]; then
    [[ -n "$local_dmg" && -n "$local_checksum" && -n "$local_signature" ]] \
        || fail "Local verification requires --dmg, --checksum, and --signature together"
    [[ "$requested_tag" != "latest" ]] \
        || fail "Local verification also requires --version"
fi
[[ "$install_directory" == /* ]] || fail "--install-dir must be an absolute path"

if [[ "$requested_tag" == "latest" ]]; then
    info "Resolving the latest GitHub release"
    latest_url="$(curl \
        --proto '=https' \
        --tlsv1.2 \
        --location \
        --fail \
        --silent \
        --show-error \
        --head \
        --output /dev/null \
        --write-out '%{url_effective}' \
        "https://github.com/$REPOSITORY/releases/latest")"
    requested_tag="${latest_url%/}"
    requested_tag="${requested_tag##*/}"
fi

if [[ ! "$requested_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    fail "Invalid release tag: $requested_tag"
fi

readonly RELEASE_TAG="$requested_tag"
readonly RELEASE_VERSION="${RELEASE_TAG#v}"
readonly ASSET_NAME="Klik-PRO-v${RELEASE_VERSION}-macos-universal.dmg"

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-installer.XXXXXX")"
mount_directory="$work_directory/mount"
allowed_signers="$work_directory/allowed_signers"
mounted=0
stage_path=""
backup_path=""
destination_app=""
install_committed=0
needs_sudo=0

run_privileged() {
    if [[ "$needs_sudo" -eq 1 ]]; then
        /usr/bin/sudo "$@"
    else
        "$@"
    fi
}

cleanup() {
    if [[ "$mounted" -eq 1 ]]; then
        hdiutil detach "$mount_directory" >/dev/null 2>&1 || true
    fi
    if [[ -n "$stage_path" && -e "$stage_path" ]]; then
        run_privileged rm -rf "$stage_path" >/dev/null 2>&1 || true
    fi
    if [[ "$install_committed" -eq 0 && -n "$backup_path" && -e "$backup_path" ]]; then
        if [[ -n "$destination_app" && -e "$destination_app" ]]; then
            run_privileged rm -rf "$destination_app" >/dev/null 2>&1 || true
        fi
        if [[ -n "$destination_app" ]]; then
            run_privileged mv "$backup_path" "$destination_app" >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$work_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$mount_directory"
printf '%s %s\n' "$RELEASE_PRINCIPAL" "$RELEASE_PUBLIC_KEY" > "$allowed_signers"

if [[ -n "$local_dmg" ]]; then
    [[ -f "$local_dmg" && -f "$local_checksum" && -f "$local_signature" ]] \
        || fail "A local DMG, checksum, or signature file does not exist"
    dmg_path="$(cd "$(dirname "$local_dmg")" && pwd)/$(basename "$local_dmg")"
    checksum_path="$(cd "$(dirname "$local_checksum")" && pwd)/$(basename "$local_checksum")"
    signature_path="$(cd "$(dirname "$local_signature")" && pwd)/$(basename "$local_signature")"
else
    dmg_path="$work_directory/$ASSET_NAME"
    checksum_path="$work_directory/$ASSET_NAME.sha256"
    signature_path="$work_directory/$ASSET_NAME.sha256.sig"
    release_base="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"

    download() {
        source_url="$1"
        destination="$2"
        curl \
            --proto '=https' \
            --tlsv1.2 \
            --location \
            --fail \
            --silent \
            --show-error \
            --retry 3 \
            --connect-timeout 15 \
            --max-time 600 \
            --output "$destination" \
            "$source_url"
    }

    info "Downloading the signed checksum for Klik PRO $RELEASE_TAG"
    if ! download "$release_base/$ASSET_NAME.sha256" "$checksum_path"; then
        fail "Release $RELEASE_TAG does not provide the expected DMG checksum"
    fi
    if ! download "$release_base/$ASSET_NAME.sha256.sig" "$signature_path"; then
        fail "Release $RELEASE_TAG predates signed Terminal installation; use the documented manual path"
    fi
fi

[[ -f "$checksum_path" ]] || fail "Checksum manifest not found"
[[ -f "$signature_path" ]] || fail "Release signature not found"

info "Authenticating the release manifest"
ssh-keygen -Y verify \
    -f "$allowed_signers" \
    -I "$RELEASE_PRINCIPAL" \
    -n "$RELEASE_NAMESPACE" \
    -s "$signature_path" \
    < "$checksum_path" >/dev/null \
    || fail "Release signature verification failed"

manifest_line="$(cat "$checksum_path")"
if [[ ! "$manifest_line" =~ ^([0-9a-f]{64})[[:space:]]+([^/]+)$ ]]; then
    fail "Checksum manifest has an unsafe or unexpected format"
fi
expected_hash="${BASH_REMATCH[1]}"
manifest_asset="${BASH_REMATCH[2]}"
[[ "$manifest_asset" == "$ASSET_NAME" ]] \
    || fail "Signed manifest names '$manifest_asset', expected '$ASSET_NAME'"

if [[ -z "$local_dmg" ]]; then
    info "Downloading $ASSET_NAME"
    download "$release_base/$ASSET_NAME" "$dmg_path"
fi
[[ -f "$dmg_path" && ! -L "$dmg_path" ]] || fail "DMG not found or is a symbolic link"

info "Verifying SHA-256 (release key $RELEASE_KEY_FINGERPRINT)"
actual_hash="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
[[ "$actual_hash" == "$expected_hash" ]] || fail "DMG checksum verification failed"

info "Verifying and mounting the disk image read-only"
hdiutil verify "$dmg_path" >/dev/null
mounted=1
hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_directory" \
    "$dmg_path" >/dev/null

source_app="$mount_directory/Klik PRO.app"
source_helper="$source_app/Contents/Helpers/Klik PRO Helper.app"
source_main_binary="$source_app/Contents/MacOS/Klik PRO"
source_helper_binary="$source_helper/Contents/MacOS/klik-pro-input"

[[ -d "$source_app" && ! -L "$source_app" ]] || fail "Verified DMG does not contain Klik PRO.app"
[[ -d "$source_helper" && ! -L "$source_helper" ]] || fail "Nested Klik PRO Helper.app is missing"
[[ -x "$source_main_binary" && ! -L "$source_main_binary" ]] || fail "Main executable is missing"
[[ -x "$source_helper_binary" && ! -L "$source_helper_binary" ]] || fail "Helper executable is missing"

plist_value() {
    plutil -extract "$2" raw -o - "$1/Contents/Info.plist"
}

[[ "$(plist_value "$source_app" CFBundleIdentifier)" == "$EXPECTED_APP_IDENTIFIER" ]] \
    || fail "Unexpected main-app bundle identifier"
[[ "$(plist_value "$source_helper" CFBundleIdentifier)" == "$EXPECTED_HELPER_IDENTIFIER" ]] \
    || fail "Unexpected helper bundle identifier"
[[ "$(plist_value "$source_app" CFBundleShortVersionString)" == "$RELEASE_VERSION" ]] \
    || fail "Main-app version does not match $RELEASE_TAG"
[[ "$(plist_value "$source_helper" CFBundleShortVersionString)" == "$RELEASE_VERSION" ]] \
    || fail "Helper version does not match $RELEASE_TAG"

codesign --verify --deep --strict --verbose=2 "$source_app" >/dev/null 2>&1 \
    || fail "App code-signature integrity check failed"
for executable in "$source_main_binary" "$source_helper_binary"; do
    architectures=" $(lipo -archs "$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] \
        || fail "Release is not universal arm64 + x86_64"
done

info "Klik PRO $RELEASE_TAG passed every authenticity and integrity check"
if [[ "$verify_only" -eq 1 ]]; then
    exit 0
fi

printf '\nThe verified app is not Apple-notarized. Installation will:\n'
printf '  • copy Klik PRO into %s\n' "$install_directory"
printf '  • replace an existing copy only after staging the new app\n'
printf '  • remove com.apple.quarantine from the verified app\n'
printf '  • preserve your Klik PRO configuration and logs\n\n'

if [[ "$assume_yes" -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        fail "Interactive confirmation requires a terminal; rerun with --yes if appropriate"
    fi
    read -r -p "Continue installing authenticated Klik PRO $RELEASE_TAG? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) fail "Installation cancelled" ;;
    esac
fi

if [[ ! -d "$install_directory" ]]; then
    if ! mkdir -p "$install_directory" 2>/dev/null; then
        needs_sudo=1
        run_privileged mkdir -p "$install_directory"
    fi
fi
if [[ ! -w "$install_directory" ]]; then
    needs_sudo=1
fi
[[ ! -L "$install_directory" ]] || fail "Install directory must not be a symbolic link"

destination_app="$install_directory/Klik PRO.app"
stage_path="$install_directory/.Klik-PRO-install-$$.app"
backup_path="$install_directory/.Klik-PRO-backup-$$.app"
case "$stage_path" in
    "$install_directory"/.Klik-PRO-install-*.app) ;;
    *) fail "Unsafe staging path" ;;
esac
case "$backup_path" in
    "$install_directory"/.Klik-PRO-backup-*.app) ;;
    *) fail "Unsafe backup path" ;;
esac
[[ ! -L "$destination_app" ]] || fail "Refusing to replace a symbolic-link destination"

info "Staging the verified application"
run_privileged rm -rf "$stage_path" "$backup_path"
run_privileged ditto --norsrc --noqtn "$source_app" "$stage_path"
run_privileged codesign --verify --deep --strict --verbose=2 "$stage_path" >/dev/null 2>&1 \
    || fail "Staged app failed code-signature verification"
run_privileged xattr -dr com.apple.quarantine "$stage_path"

# Quit the settings app before its bundle is replaced. The TERM fallback is used only
# when a running copy does not respond to a normal Apple-event quit request.
if pgrep -x "Klik PRO" >/dev/null 2>&1; then
    osascript -e 'tell application id "local.klik-pro" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        pgrep -x "Klik PRO" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -x "Klik PRO" >/dev/null 2>&1; then
        pkill -TERM -x "Klik PRO" >/dev/null 2>&1 || true
    fi
fi

# Stop only Klik PRO's per-user services. Failures are harmless when this is a first install.
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.klik-pro.input.plist" \
    >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.klik-pro.menu.plist" \
    >/dev/null 2>&1 || true

if [[ -e "$destination_app" ]]; then
    info "Keeping the existing app as a temporary rollback copy"
    run_privileged mv "$destination_app" "$backup_path"
fi

if ! run_privileged mv "$stage_path" "$destination_app"; then
    if [[ -e "$backup_path" && ! -e "$destination_app" ]]; then
        run_privileged mv "$backup_path" "$destination_app" || true
    fi
    fail "Unable to activate the new app; the previous copy was restored when possible"
fi
stage_path=""

if ! run_privileged codesign --verify --deep --strict --verbose=2 "$destination_app" \
    >/dev/null 2>&1; then
    run_privileged rm -rf "$destination_app"
    if [[ -e "$backup_path" ]]; then
        run_privileged mv "$backup_path" "$destination_app"
    fi
    fail "Installed app verification failed; the previous copy was restored"
fi

if [[ -e "$backup_path" ]]; then
    run_privileged rm -rf "$backup_path"
fi
backup_path=""
install_committed=1

info "Installed authenticated Klik PRO $RELEASE_TAG"
open "$destination_app"
printf '\nGrant Klik PRO Helper access when onboarding opens.\n'
