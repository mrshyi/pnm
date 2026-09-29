#!/usr/bin/env bash

pnm_render_xray_unit() {
    cat <<'EOF'
[Unit]
Description=PNM Xray Core
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
CapabilityBoundingSet=
AmbientCapabilities=
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

pnm_render_hysteria_unit() {
    cat <<'EOF'
[Unit]
Description=PNM Official Hysteria2 Core
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=hysteria
Group=hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
CapabilityBoundingSet=
AmbientCapabilities=
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

pnm_unit_validate_text() {
    local unit_text="${1:?unit text required}"
    local expected_user="${2:?expected user required}"
    local expected_binary="${3:?expected binary required}"

    [[ "$unit_text" == *$'\nUser='"$expected_user"$'\n'* ]] || return 1
    [[ "$unit_text" == *"ExecStart=$expected_binary"* ]] || return 1
    [[ "$unit_text" == *$'NoNewPrivileges=true'* ]] || return 1
    [[ "$unit_text" == *$'ProtectSystem=strict'* ]] || return 1
    [[ "$unit_text" == *$'CapabilityBoundingSet='* ]] || return 1
}

pnm_systemd_install_unit() {
    local unit_name="${1:?unit name required}"
    local renderer="${2:?unit renderer required}"
    local target_dir="${3:-/etc/systemd/system}"
    local target temp_file

    [[ "$unit_name" =~ ^[a-z0-9@_.-]+\.service$ ]] || return "$PNM_EXIT_CONFIG"
    [[ -d "$target_dir" && ! -L "$target_dir" && -w "$target_dir" ]] || return "$PNM_EXIT_CANTCREAT"
    target="$target_dir/$unit_name"
    [[ ! -e "$target" || ! -L "$target" ]] || return "$PNM_EXIT_CONFIG"
    temp_file="$(mktemp "$target_dir/.pnm-unit.XXXXXXXX")" || return "$PNM_EXIT_CANTCREAT"
    if ! "$renderer" >"$temp_file"; then
        rm -f -- "$temp_file"
        return "$PNM_EXIT_SOFTWARE"
    fi
    chmod 0644 -- "$temp_file"
    mv -f -- "$temp_file" "$target" || {
        rm -f -- "$temp_file"
        return "$PNM_EXIT_CANTCREAT"
    }
}

pnm_systemd_validate_unit_file() {
    local unit_file="${1:?unit file required}"

    [[ -f "$unit_file" && ! -L "$unit_file" ]] || return "$PNM_EXIT_CONFIG"
    pnm_command_exists systemd-analyze || return "$PNM_EXIT_UNAVAILABLE"
    systemd-analyze verify "$unit_file" >/dev/null 2>&1
}
