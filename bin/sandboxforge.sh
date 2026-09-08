#!/usr/bin/env bash
set -euo pipefail

create_sandbox() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "sandboxforge: create requires a sandbox name" >&2
        return 1
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "sandobxforge: sandbox '$name' already exists" >&2
        return 1
    fi
    local image="sandboxforge-base:latest"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        docker build -t "$image" "$script_dir"
    fi
    docker run -d --name "$name" "$image"
}

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        create)
            create_sandbox "${1:-}"
            ;;
        enter)
            echo "[enter] would enter sandbox: ${1:-<none>}"
            ;;
        destroy)
            echo "[destroy] would destroy sandbox: ${1:-<none>}"
            ;;
        *)
            echo "sandboxforge: unknown command '${cmd}'" >&2
            exit 1
            ;;
   esac
}

main "$@"
