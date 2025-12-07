#!/usr/bin/env bash
# Compute sha256sum for all non-hidden files in a directory (excluding any path component that starts with a dot),
# sort files by filename (basename), and save the results to .sha256sum-current.txt in that directory.
# Each output line: <sha256><TAB><filename>
# Usage: ./sha256-all.sh [directory]
# Defaults to current directory when no argument is given.
set -euo pipefail

dir="${1:-.}"
outfile="${dir%/}/.sha256sum-current.txt"

# Ensure required program exists
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

# sorted_pipe: reads NUL-separated file paths from stdin and writes NUL-separated file paths
# sorted by basename to stdout. Prefer python3 (safe, handles arbitrary bytes), fall back to sort -z
# which sorts by the full path (not basename). Final fallback uses newline sort (less safe).
sorted_pipe() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import sys, os
data = sys.stdin.buffer.read().split(b'\0')
data = [d for d in data if d]
# Sort by basename (bytes)
pairs = [(os.path.basename(d), d) for d in data]
pairs.sort(key=lambda x: x[0])
sys.stdout.buffer.write(b'\0'.join([p[1] for p in pairs]))
PY
  elif printf '' | sort -z >/dev/null 2>&1; then
    # sort -z sorts by the entire path (byte-wise)
    sort -z
  else
    # Last resort: convert NUL to newline, sort, convert back. May mishandle filenames with newlines.
    tr '\0' '\n' | sort | tr '\n' '\0'
  fi
}

# Find regular files while excluding any file or directory whose name starts with a dot (hidden),
# output NUL-separated filenames to safely handle special characters, then sort them and compute sha256.
find "$dir" -mindepth 1 -path '*/.*' -prune -o -type f -print0 |
  sorted_pipe |
  while IFS= read -r -d '' file; do
    # Defensive: skip the tmpfile itself if encountered
    [ "$file" = "$tmpfile" ] && continue
    # Compute hash (first field of sha256sum) and print with a tab separator.
    hash="$(sha256sum -- "$file" | awk '{print $1}')"
    printf '%s\t%s\n' "$hash" "$file" >>"$tmpfile"
  done

# Move temp file into place (atomic on same filesystem) and set safe permissions
mv -- "$tmpfile" "$outfile"
chmod 0644 "$outfile"
# Clear trap since we've moved the file into place
trap - EXIT

printf '%s\n' "Saved sha256s (sorted by filename) to: $outfile"
