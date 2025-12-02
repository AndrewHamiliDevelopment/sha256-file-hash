#!/usr/bin/env bash
# Compute sha256sum for all non-hidden files in a directory (excluding any path component that starts with a dot)
# and save the results to .sha256sum-current.txt in that directory.
# Usage: ./sha256-all.sh [directory]
# Defaults to current directory when no argument is given.
set -euo pipefail

dir="${1:-.}"
outfile="${dir%/}/.sha256sum-current.txt"

# Ensure sha256sum exists
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '%s\n' "Error: sha256sum is not installed or not in PATH." >&2
  exit 2
fi

# Ensure directory exists
if [ ! -d "$dir" ]; then
  printf '%s\n' "Error: '%s' is not a directory." "$dir" >&2
  exit 3
fi

# Create a temp file in the target directory so the final move is atomic on the same filesystem.
tmpfile="$(mktemp -p "$dir" ".sha256sum-current.txt.tmp.XXXXXX")"
# Ensure tmpfile is removed on exit if anything goes wrong
trap 'rm -f -- "$tmpfile"' EXIT

# Find regular files while excluding any file or directory whose name starts with a dot (hidden),
# output NUL-separated filenames to safely handle special characters, and compute sha256sum.
find "$dir" -mindepth 1 -path '*/.*' -prune -o -type f -print0 |
  while IFS= read -r -d '' file; do
    # Skip the temp file itself if it's ever encountered (it is hidden and normally pruned, but be defensive)
    [ "$file" = "$tmpfile" ] && continue
    sha256sum -- "$file" >>"$tmpfile"
  done

# Move temp file into place (atomic on same filesystem) and set safe permissions
mv -- "$tmpfile" "$outfile"
chmod 0644 "$outfile"
# Clear trap since we've moved the file into place
trap - EXIT

printf '%s\n' "Saved sha256s to: $outfile"
