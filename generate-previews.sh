#!/usr/bin/env bash
set -euo pipefail

PREVIEW_ROOT="previews"
SIZES=(200 800)
FORCE=0

usage() {
  echo "Usage: $0 [--force|-f]"
  echo
  echo "Generates preview sizes: ${SIZES[*]}"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

# --- Detect ImageMagick (IM6 / IM7 compatible) ---
if command -v magick >/dev/null 2>&1; then
  IM_CMD="magick"
elif command -v convert >/dev/null 2>&1; then
  IM_CMD="convert"
else
  die "ImageMagick not found. Install with: sudo zypper install ImageMagick"
fi

# --- Check optipng ---
command -v optipng >/dev/null 2>&1 || \
  die "optipng not found. Install with: sudo zypper install optipng"

# --- Args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

shopt -s nullglob
PNGS=( *.png )
shopt -u nullglob

[[ ${#PNGS[@]} -gt 0 ]] || die "No .png files found."

IN_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1

# Decide whether a preview must be regenerated.
# Git does not preserve mtimes (checkout/pull stamps files with the current
# time), so a plain mtime comparison flags untouched badges as stale and
# re-encodes them, producing byte-different output with other ImageMagick /
# optipng versions. Use git history instead; fall back to mtime outside git.
needs_update() {
  local img=$1 out=$2
  [[ -f "$out" ]] || return 0                         # preview missing

  if [[ $IN_GIT -eq 0 ]]; then
    [[ "$img" -nt "$out" ]]
    return
  fi

  # Source modified, staged or untracked: regenerate unless the preview was
  # already written after the source was last edited.
  if [[ -n "$(git status --porcelain -- "$img")" ]]; then
    [[ "$img" -nt "$out" ]]
    return
  fi

  local src_t out_t
  src_t=$(git log -1 --format=%ct -- "$img")
  out_t=$(git log -1 --format=%ct -- "$out")
  [[ -z "$out_t" ]] && return 0                       # preview never committed
  (( src_t > out_t ))
}

for size in "${SIZES[@]}"; do
  outdir="${PREVIEW_ROOT}/${size}"
  mkdir -p "$outdir"

  for img in "${PNGS[@]}"; do
    base="$(basename "$img")"
    out="${outdir}/${base}"

    if [[ $FORCE -eq 0 ]] && ! needs_update "$img" "$out"; then
      echo "Skipping ${img} (${size}px up-to-date)"
      continue
    fi

    tmp="$(mktemp --suffix=.png)"

    echo "Generating ${img} → ${out} (${size}px)"

    "$IM_CMD" "$img" \
      -resize "${size}x${size}" \
      -filter point \
      -strip \
      -define png:compression-level=6 \
      "$tmp"

    optipng -o7 -quiet "$tmp" >/dev/null 2>&1 || true

    if [[ -f "$out" ]] && cmp -s "$tmp" "$out"; then
      rm -f "$tmp"
      touch "$out"
    else
      mv -f "$tmp" "$out"
    fi
  done
done

echo "Done. Generated sizes: ${SIZES[*]}"
