#!/usr/bin/env bash
set -euo pipefail

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        create)
            echo "[create] would create sandbox: ${1:-<none>}"
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
