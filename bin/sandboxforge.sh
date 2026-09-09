#!/usr/bin/env bash
set -euo pipefail

log_action() {
    local action="$1"
    local name="$2"
    local result="$3"
    local log_dir="$HOME/.sandboxforge"
    local log_file="$log_dir/audit.log"
    mkdir -p "$log_dir"
    printf '%s %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$action" "$name" "$result" >> "$log_file"
}

create_sandbox() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "sandboxforge: create requires a sandbox name" >&2
        log_action "create" "-" "refused"
        return 1
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "sandboxforge: sandbox '$name' already exists" >&2
        log_action "create" "$name" "refused"
        return 1
    fi
    local image="sandboxforge-base:latest"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        docker build -t "$image" "$script_dir"
    fi
    docker run -d --name "$name" "$image"
    log_action "create" "$name" "ok"
}

enter_sandbox() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "sandboxforge: enter requires a sandbox name" >&2
        log_action "enter" "-" "refused"
        return 1
    fi
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "sandboxforge: no sandbox named '$name'" >&2
        log_action "enter" "$name" "refused"
        return 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
        echo "sandboxforge: sandbox '$name' exists but is stopped (docker start $name)" >&2
        log_action "enter" "$name" "refused"
        return 1
    fi
    log_action "enter" "$name" "ok"
    docker exec -it "$name" bash
}

destroy_sandbox() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "sandboxforge: destroy requires a sandbox name" >&2
        log_action "destroy" "-" "refused"
        return 1
    fi
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "sandboxforge: no sandbox named '$name'" >&2
        log_action "destroy" "$name" "refused"
        return 1
    fi

    local reply
    read -r -p "Destroy sandbox '$name'? [y/N] " reply
    if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
        echo "sandboxforge: cancelled"
        log_action "destroy" "$name" "cancelled"
        return 0
    fi
    docker rm -v -f "$name" >/dev/null
    echo "sandboxforge: destroyed '$name'"
    log_action "destroy" "$name" "ok"
}

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        create)
            create_sandbox "${1:-}"
            ;;
        enter)
            enter_sandbox "${1:-}"
            ;;
        destroy)
            destroy_sandbox "${1:-}"
            ;;
        *)
            echo "sandboxforge: unknown command '${cmd}'" >&2
            exit 1
            ;;
   esac
}

main "$@"
