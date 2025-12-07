#!/usr/bin/env bash
# Minimal script (no python) that:
# - Finds all non-hidden regular files in a directory (no path component starts with a dot)
# - Sorts files by filename (basename) before hashing (requires GNU sort -z)
# - Writes lines as: <sha256><TAB><filename> into .sha256sum-current.txt in the target directory
# Usage: ./sha256-all.sh [directory]
set -euo pipefail

dir="${1:-.}"
outfile="${dir%/}/.sha256sum-current.txt"

# Require tools
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "Error: sha256sum is required but not found in PATH." >&2
  exit 2
fi
if ! printf '' | sort -z >/dev/null 2>&1; then
  printf '%s\n' "Error: this script requires GNU sort with -z support (coreutils). Install coreutils or use a system with GNU sort." >&2
  exit 4
fi

if [ ! -d "$dir" ]; then
  printf '%s\n' "Error: '%s' is not a directory." "$dir" >&2
  exit 3
fi

tmpfile="$(mktemp -p "$dir" ".sha256sum-current.txt.tmp.XXXXXX")"
trap 'rm -f -- "$tmpfile"' EXIT

# Pipeline explanation:
# - find ... -print0 gives NUL-separated file paths
# - the inline while converts each file into a NUL-separated "basename<TAB>fullpath" record
# - sort -z -t$'\t' -k1,1 sorts records by the basename field (NUL-separated records)
# - the final read loop extracts fullpath and computes the hash, writing "<hash><TAB><fullpath>\n"
find "$dir" -mindepth 1 -path '*/.*' -prune -o -type f -print0 |
  ( while IFS= read -r -d '' f; do printf '%s\t%s\0' "$(basename "$f")" "$f"; done ) |
  sort -z -t$'\t' -k1,1 |
  while IFS= read -r -d '' rec; do
    # split on first tab: basename_field="${rec%%$'\t'*}" ; fullpath="${rec#*$'\t'}"
    fullpath="${rec#*$'\t'}"
    [ "$fullpath" = "$tmpfile" ] && continue
    hash="$(sha256sum -- "$fullpath" | awk '{print $1}')"
    printf '%s\t%s\n' "$hash" "$fullpath" >>"$tmpfile"
  done

mv -- "$tmpfile" "$outfile"
chmod 0644 "$outfile"
trap - EXIT

printf '%s\n' "Saved sha256s (sorted by filename) to: $outfile"
