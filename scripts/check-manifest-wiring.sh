#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0

# Complement to scripts/validate.sh, which is vendored from upstream
# (fluxcd/flux2-kustomize-helm-example) and should be kept unmodified so it can
# be updated cleanly.
#
# This script exists because of a gap validate.sh cannot see. That script
# validates standalone manifests, then validates the output of building each
# kustomize overlay. A manifest file that sits inside a kustomize directory but
# is never listed in that directory's kustomization.yaml is invisible to both
# passes: the build never emits it, and the standalone pass skips it precisely
# because it lives in a kustomize directory. The result validates clean while
# the manifest is silently never applied.
#
# So: every *.yaml / *.yml file inside a kustomize directory must be
# acknowledged by the kustomization that owns it. A filename appearing anywhere
# in the owning kustomization counts, including a commented-out entry — that is
# the convention used in this repo to park a manifest deliberately (see
# apps/base/kps/recording-rules.yaml). Parked files are reported as INFO;
# files mentioned nowhere are errors.
#
# Matching is a text heuristic on the filename, not a parse of the
# kustomization. That is deliberate: it keeps the script free of any
# dependency beyond bash, find, grep, and sed.

# Prerequisites
# - bash, find, grep, sed (no kustomize, no flux-schema, no network)

# Usage examples:
#   ./scripts/check-manifest-wiring.sh
#   ./scripts/check-manifest-wiring.sh -d ./apps -e ./apps/base/kps

set -o errexit
set -o pipefail

errors=0
parked_count=0

root_dir="."
exclude_dirs=()
kustomize_config="kustomization.yaml"

usage() {
  echo "Usage: $0 [-d <dir>] [-e <dir>]... [-h]"
  echo ""
  echo "Report manifests inside a kustomize directory that no kustomization wires up."
  echo ""
  echo "Options:"
  echo "  -d, --dir <dir>        Root directory to check (default: current directory)"
  echo "  -e, --exclude <dir>    Directory to exclude (can be repeated)"
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
      -e|--exclude)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR - --exclude requires a directory argument" >&2
          exit 1
        fi
        exclude_dirs+=("./${2#./}")
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

is_excluded_dir() {
  local path dir
  path="$(normalize_path "$1")"
  for dir in "${exclude_dirs[@]}"; do
    dir="$(normalize_path "$dir")"
    if [[ "$path" == "$dir"/* || "$path" == "$dir" ]]; then
      return 0
    fi
  done
  return 1
}

# Normalize a path by stripping leading "./" for consistent comparisons
normalize_path() {
  local p="${1#./}"
  echo "${p%/}"
}

# Print a path relative to root_dir, to match the paths validate.sh reports
rel_path() {
  local p r
  p="$(normalize_path "$1")"
  r="$(normalize_path "$root_dir")"
  if [[ "$r" != "." && "$p" == "$r"/* ]]; then
    p="${p#"$r"/}"
  fi
  echo "$p"
}

# Print the nearest ancestor directory of a file that holds a kustomization.
# Returns 1 when no ancestor does (a standalone manifest outside any overlay).
owner_kustomization() {
  local p
  p="$(normalize_path "$(dirname "$1")")"
  while [[ -n "$p" && "$p" != "." && "$p" != "/" ]]; do
    if [[ -f "$p/$kustomize_config" ]]; then
      echo "$p"
      return 0
    fi
    p="$(normalize_path "$(dirname "$p")")"
  done
  if [[ -f "$root_dir/$kustomize_config" ]]; then
    echo "$(normalize_path "$root_dir")"
    return 0
  fi
  return 1
}

# Escape a filename so it can be used as a literal grep -E pattern
escape_regex() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|\\]/\\&/g'
}

# A filename counts as referenced when it appears as a whole token at the end of
# a list entry, with an optional closing quote and trailing comment.
build_pattern() {
  echo "(^|[^[:alnum:]_.-])$(escape_regex "$1")\"?[[:space:]]*(#.*)?$"
}

check_wiring() {
  echo "INFO - Checking manifest wiring under $root_dir"
  local file owner base pattern
  while IFS= read -r -d $'\0' file; do
    if ! owner="$(owner_kustomization "$file")"; then
      continue
    fi
    if is_excluded_dir "$(dirname "$file")"; then
      continue
    fi
    base="$(basename "$file")"
    pattern="$(build_pattern "$base")"
    if grep -qE "$pattern" "$owner/$kustomize_config"; then
      # Mentioned, but only in a comment: present yet deliberately parked.
      if ! grep -v '^[[:space:]]*#' "$owner/$kustomize_config" | grep -qE "$pattern"; then
        echo "INFO - $(rel_path "$file") is parked in $owner/$kustomize_config (listed as a comment)"
        parked_count=$((parked_count + 1))
      fi
      continue
    fi
    echo "ERROR - $(rel_path "$file") is not referenced by $owner/$kustomize_config" >&2
    errors=$((errors + 1))
  done < <(find "$root_dir" -mindepth 1 -name '.*' -prune -o -type f \
    \( -name '*.yaml' -o -name '*.yml' \) ! -name "$kustomize_config" -print0)
}

report_results() {
  if [[ $errors -gt 0 ]]; then
    echo "ERROR - Manifest wiring failed: ${errors} unreferenced manifest(s)" >&2
    exit 1
  fi
  echo "INFO - Manifest wiring passed (${parked_count} parked)"
}

# Main
parse_args "$@"
if [[ ! -d "$root_dir" ]]; then
  echo "ERROR - directory not found: $root_dir" >&2
  exit 1
fi
check_wiring
report_results
