#!/usr/bin/env bash

# UI for the x installer: uses gum if available and falls back to plain text
# prompts otherwise (TTY without gum or non-interactive tests).

have_gum() {
    # X_INSTALL_PLAIN=1 forces the numbered fallback prompts. This is used by
    # the interactive serial test harness and by headless environments.
    [[ "${X_INSTALL_PLAIN:-0}" == "1" ]] && return 1
    command -v gum >/dev/null 2>&1
}

ask_value() {
    local var="$1" prompt="$2" value
    if have_gum; then
        value="$(gum input --placeholder "$prompt")" || value=""
    else
        printf '%s: ' "$prompt"
        IFS= read -r value
    fi
    printf -v "$var" '%s' "$value"
}

ask_password() {
    local var="$1" prompt="$2" value
    if have_gum; then
        value="$(gum input --password --placeholder "$prompt")" || value=""
    else
        printf '%s: ' "$prompt"
        IFS= read -r -s value
        printf '\n'
    fi
    printf -v "$var" '%s' "$value"
}

select_one() {
    local var="$1" prompt="$2"
    shift 2
    local items=("$@") value=""
    if have_gum; then
        value="$(printf '%s\n' "${items[@]}" | gum choose --header "$prompt")" || value=""
    else
        local i
        printf '%s\n' "$prompt"
        for i in "${!items[@]}"; do
            printf '  %d) %s\n' "$((i + 1))" "${items[$i]}"
        done
        printf 'choose (1-%d): ' "${#items[@]}"
        IFS= read -r sel
        sel="${sel:-1}"
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#items[@]} )); then
            value="${items[$((sel - 1))]}"
        fi
    fi
    printf -v "$var" '%s' "$value"
}

confirm_yes() {
    local prompt="$1" default="${2:-n}"
    local dflag
    if have_gum; then
        [[ "$default" == "y" ]] && dflag="--default=true" || dflag="--default=false"
        gum confirm $dflag "$prompt"
    else
        local resp label
        if [[ "$default" == "y" ]]; then
            label="Y/n"
        else
            label="y/N"
        fi
        printf '%s [%s]: ' "$prompt" "$label"
        IFS= read -r resp
        resp="${resp:-$default}"
        [[ "$resp" =~ ^[sSyY] ]]
    fi
}
