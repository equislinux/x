#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/airootfs/root/x-installer/kernel-signatures.sh"

tmp="$(mktemp -d)"
signer="$tmp/signer"
verifier="$tmp/verifier"
cleanup() {
    gpgconf --homedir "$signer" --kill gpg-agent 2>/dev/null || true
    gpgconf --homedir "$verifier" --kill gpg-agent 2>/dev/null || true
    rm -rf -- "$tmp"
}
trap cleanup EXIT
mkdir -m 700 "$signer" "$verifier"

identity='X installer test <installer-test@example.invalid>'
gpg --no-options --batch --homedir "$signer" \
    --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$identity" ed25519 sign 1d
gpg --no-options --batch --homedir "$signer" --export "$identity" |
    gpg --no-options --batch --homedir "$verifier" --import

kernel="$tmp/kernel.pkg.tar.zst"
headers="$tmp/headers.pkg.tar.zst"
printf 'test kernel\n' > "$kernel"
printf 'test headers\n' > "$headers"
for package in "$kernel" "$headers"; do
    gpg --no-options --batch --homedir "$signer" \
        --pinentry-mode loopback --passphrase '' --detach-sign "$package"
done

expect_rejection() {
    local expected="$1" output
    if output="$(verify_bundled_kernel_signatures "$verifier" "$kernel" "$headers" 2>&1)"; then
        printf 'FAIL: expected rejection: %s\n' "$expected" >&2
        exit 1
    fi
    if ! grep -Fq -- "$expected" <<<"$output"; then
        printf 'FAIL: unexpected diagnostic:\n%s\n' "$output" >&2
        exit 1
    fi
    printf 'ok - %s\n' "$expected"
}

verify_bundled_kernel_signatures "$verifier" "$kernel" "$headers"
printf 'ok - both valid signatures accepted\n'

for package in "$kernel" "$headers"; do
    mv -- "$package.sig" "$package.sig.saved"
    expect_rejection "missing kernel signature: $package.sig"
    mv -- "$package.sig.saved" "$package.sig"

    cp -- "$package" "$package.saved"
    printf 'modified after signing\n' >> "$package"
    expect_rejection "kernel signature verification failed: $package"
    mv -- "$package.saved" "$package"
done

printf 'installer-kernel-signatures: OK\n'
