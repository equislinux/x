#!/usr/bin/env bash
# Early network setup: Ethernet first, then an interactive WiFi picker.
# This module is intentionally non-destructive and can fall back to the
# bundled xpm when no network is available.

network_online() {
    curl -fsSI --max-time 8 https://equislinux.github.io/x-repo/repo/x86_64/x.db.sig \
        >/dev/null 2>&1
}

network_ui_ok()   { if have_gum; then gum style --foreground 2 "✔ $*"; else printf '✔ %s\n' "$*"; fi; }
network_ui_warn() { if have_gum; then gum style --foreground 3 "! $*"; else printf '! %s\n' "$*" >&2; fi; }
network_ui_err()  { if have_gum; then gum style --foreground 1 "✘ $*"; else printf '✘ %s\n' "$*" >&2; fi; }

network_start_manager() {
    if ! command -v nmcli >/dev/null 2>&1; then
        network_ui_warn "NetworkManager is not available"
        return 1
    fi
    systemctl start NetworkManager >/dev/null 2>&1 || true
    nmcli networking on >/dev/null 2>&1 || true
    nmcli radio wifi on >/dev/null 2>&1 || true
    command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 15); do
        nmcli -t general status >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

network_wait_online() {
    local seconds="${1:-30}" i
    for ((i = 0; i < seconds; i += 2)); do
        network_online && return 0
        sleep 2
    done
    return 1
}

network_wifi_networks() {
    nmcli -t -f SSID device wifi list --rescan yes 2>/dev/null |
        sed 's/^: *//' |
        sed 's/\\:/:/g' |
        awk 'NF && !seen[$0]++ && $0 != "--"'
}

network_connect_wifi() {
    local ssid="$1" password="${2:-}"
    local output
    if [[ -n "$password" ]]; then
        # Feed the password on stdin so it never appears in the process list.
        if printf '%s\n' "$password" | nmcli --ask device wifi connect "$ssid" >/tmp/x-wifi.log 2>&1; then
            :
        else
            output="$(tail -n 3 /tmp/x-wifi.log 2>/dev/null | tr '\n' ' ')"
            network_ui_err "Could not connect to '$ssid'${output:+: $output}"
            rm -f /tmp/x-wifi.log
            return 1
        fi
    else
        if ! nmcli device wifi connect "$ssid" >/tmp/x-wifi.log 2>&1; then
            output="$(tail -n 3 /tmp/x-wifi.log 2>/dev/null | tr '\n' ' ')"
            network_ui_err "Could not connect to '$ssid'${output:+: $output}"
            rm -f /tmp/x-wifi.log
            return 1
        fi
    fi
    rm -f /tmp/x-wifi.log
    if network_wait_online 45; then
        X_WIFI_USED=1
        X_WIFI_CONNECTION="$ssid"
        network_ui_ok "Connected to '$ssid'"
        return 0
    fi
    network_ui_err "WiFi connected, but HTTPS is unreachable"
    return 1
}

network_autoinstall() {
    [[ -f /run/cidata/x-install.json || "${X_AUTO:-0}" == "1" ]]
}

network_setup() {
    echo "== network setup"
    if network_online; then
        network_ui_ok "Network available via Ethernet"
        return 0
    fi
    network_start_manager || true
    if network_wait_online 20; then
        network_ui_ok "Network available via Ethernet"
        return 0
    fi

    local ssid="${X_WIFI_SSID:-}" password="${X_WIFI_PASSWORD:-}"
    if [[ -n "$ssid" ]]; then
        network_ui_warn "Connecting to configured WiFi: $ssid"
        network_connect_wifi "$ssid" "$password" && return 0
    fi
    if network_autoinstall || [[ ! -t 0 ]]; then
        network_ui_err "No network and cannot prompt for WiFi in unattended mode"
        return 1
    fi

    local i networks sel password_try
    for ((i = 0; i < 3; i++)); do
        mapfile -t networks < <(network_wifi_networks)
        if [[ "${#networks[@]}" -eq 0 ]]; then
            network_ui_warn "No WiFi networks detected"
            confirm_yes "Retry the scan?" y || break
            continue
        fi
        networks+=("Enter SSID manually")
        select_one sel "Select a WiFi network" "${networks[@]}"
        [[ -n "$sel" ]] || { network_ui_warn "Selection cancelled"; return 1; }
        if [[ "$sel" == "Enter SSID manually" ]]; then
            ask_value sel "SSID"
            [[ -n "$sel" ]] || continue
        fi
        ask_password password_try "WiFi password for $sel (empty if open)"
        if network_connect_wifi "$sel" "$password_try"; then
            return 0
        fi
        network_ui_warn "Try another network or check the password"
    done
    network_ui_err "Could not establish a network connection"
    return 1
}

network_persist_to_target() {
    local target="$1"
    [[ "${X_WIFI_USED:-0}" == "1" ]] || return 0
    [[ -d /etc/NetworkManager/system-connections ]] || return 0
    local dest="$target/etc/NetworkManager/system-connections"
    mkdir -p "$dest"
    local file
    for file in /etc/NetworkManager/system-connections/*.nmconnection; do
        [[ -f "$file" ]] || continue
        install -Dm600 "$file" "$dest/$(basename "$file")"
    done
    echo "== WiFi connection copied to target"
}
