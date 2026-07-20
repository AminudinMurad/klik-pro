#!/bin/bash

# Signs Klik PRO release checksum manifests with the dedicated release key.
# The private key must stay outside the repository. The matching public key is
# intentionally duplicated here and in install.sh so using the wrong key fails closed.

set -euo pipefail

readonly EXPECTED_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRinZxINTO5M8kTyrRXphibZXsiGSj/Q0dIjegq8qXd"
readonly RELEASE_PRINCIPAL="klik-pro-release"
readonly RELEASE_NAMESPACE="klik-pro-release"
readonly DEFAULT_KEY_PATH="$HOME/.config/klik-pro/release-signing/id_ed25519"
readonly KEY_PATH="${KLIK_PRO_RELEASE_SIGNING_KEY:-$DEFAULT_KEY_PATH}"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 MANIFEST.sha256 [MANIFEST.sha256 ...]" >&2
    exit 64
fi

[[ -f "$KEY_PATH" ]] || {
    echo "Release-signing key not found: $KEY_PATH" >&2
    exit 1
}
key_mode="$(stat -f '%Lp' "$KEY_PATH")"
if (( (8#$key_mode & 077) != 0 )); then
    echo "Release-signing key must not be readable by group or other users: $KEY_PATH" >&2
    exit 1
fi

actual_public_key="$(ssh-keygen -y -f "$KEY_PATH" | awk '{ print $1 " " $2 }')"
[[ "$actual_public_key" == "$EXPECTED_PUBLIC_KEY" ]] || {
    echo "Refusing to sign with a key that does not match install.sh" >&2
    exit 1
}

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/klik-pro-sign.XXXXXX")"
trap 'rm -rf "$work_directory"' EXIT
printf '%s %s\n' "$RELEASE_PRINCIPAL" "$EXPECTED_PUBLIC_KEY" \
    > "$work_directory/allowed_signers"

for manifest in "$@"; do
    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        echo "Manifest not found or is a symbolic link: $manifest" >&2
        exit 1
    }
    [[ "$manifest" == *.sha256 ]] || {
        echo "Release manifest must end in .sha256: $manifest" >&2
        exit 1
    }

    signature="$manifest.sig"
    rm -f "$signature"
    ssh-keygen -Y sign \
        -f "$KEY_PATH" \
        -n "$RELEASE_NAMESPACE" \
        "$manifest" >/dev/null
    ssh-keygen -Y verify \
        -f "$work_directory/allowed_signers" \
        -I "$RELEASE_PRINCIPAL" \
        -n "$RELEASE_NAMESPACE" \
        -s "$signature" \
        < "$manifest" >/dev/null
    echo "Signed: $signature"
done
