#!/usr/bin/env bash

verify_bundled_kernel_signatures() {
    local gpgdir="$1" package

    for package in "$2" "$3"; do
        if [[ ! -f "$package.sig" ]]; then
            printf 'installer: missing kernel signature: %s\n' "$package.sig" >&2
            return 1
        fi

        if ! gpg --no-options --batch --no-auto-key-retrieve \
            --homedir "$gpgdir" --verify "$package.sig" "$package"; then
            printf 'installer: kernel signature verification failed: %s\n' "$package" >&2
            return 1
        fi
    done
}
