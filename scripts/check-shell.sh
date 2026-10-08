#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0

# Companion to scripts/validate.sh, which only covers manifests. Lints every
# shell script in the repo.
#
# Prerequisites
# - shellcheck (brew install shellcheck)

# Usage examples:
#   ./scripts/check-shell.sh
#   ./scripts/check-shell.sh -d ./scripts
#   ./scripts/check-shell.sh -S error

set -o errexit
set -o pipefail

root_dir="."
severity="warning"

usage() {
  echo "Usage: $0 [-d <dir>] [-S <severity>] [-h]"
  echo ""
  echo "Run shellcheck over every *.sh file under a directory."
  echo ""
  echo "Options:"
  echo "  -d, --dir <dir>        Root directory to check (default: current directory)"
  echo "  -S, --severity <level> error, warning, info, or style (default: warning)"
  echo "  -h, --help             Show this help message"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR - --dir requires a directory argument" >&2
          exit 1
        fi
        root_dir="${2%/}"
        shift 2
        ;;
      -S|--severity)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR - --severity requires an argument" >&2
          exit 1
        fi
        severity="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR - Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

check_scripts() {
  echo "INFO - Running shellcheck -S $severity under $root_dir"
  local file failures=0 count=0
  while IFS= read -r -d $'\0' file; do
    count=$((count + 1))
    if ! shellcheck -S "$severity" "$file"; then
      failures=$((failures + 1))
    fi
  done < <(find "$root_dir" -type d -name '.git' -prune -o -type f -name '*.sh' -print0)

  if [[ $count -eq 0 ]]; then
    echo "ERROR - No *.sh files found under $root_dir" >&2
    exit 1
  fi
  if [[ $failures -gt 0 ]]; then
    echo "ERROR - Shellcheck failed: ${failures} of ${count} script(s)" >&2
    exit 1
  fi
  echo "INFO - Shellcheck passed (${count} script(s))"
}

# Main
parse_args "$@"
if [[ ! -d "$root_dir" ]]; then
  echo "ERROR - directory not found: $root_dir" >&2
  exit 1
fi
if ! command -v shellcheck > /dev/null ; then
  echo "ERROR - shellcheck not found on PATH" >&2
  exit 1
fi
check_scripts
