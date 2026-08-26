#!/usr/bin/env bash
#
# Regenerates media/textures/AtfCasino/Cards/<rank><suit>.png from TemplateCards.png.
#
# Cells are located by scanning for the atlas' separator colour (sampled from its top-left pixel)
# rather than by fixed offsets, so redrawing or respacing the fronts needs no change here.
#
# back.png is hand-authored and is left alone.

set -euo pipefail

readonly RANKS=(2 3 4 5 6 7 8 9 10 J Q K A)
readonly SUITS=(h c d s)

# The separator lines are several pixels thick and not perfectly even, which leaves the odd
# one-pixel seam between them. Anything narrower than a plausible card is one of those.
readonly MIN_CARD=16

# The atlas is hand-drawn and the occasional cell sits a pixel out. Pad those back to the common
# size so every texture scales identically in the UI, but treat a bigger gap as a real mistake.
# Proportional, so the check still holds if the atlas is ever redrawn at a different scale.
readonly SIZE_TOLERANCE_PERCENT=2

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ATLAS="$ROOT/TemplateCards.png"
readonly OUT="$ROOT/media/textures/AtfCasino/Cards"

die() {
    echo "slice-cards: $*" >&2
    exit 1
}

if command -v magick >/dev/null 2>&1; then
    im() { magick "$@"; }
elif command -v convert >/dev/null 2>&1; then
    im() { convert "$@"; }
else
    die "ImageMagick is required (install 'imagemagick')"
fi

[[ -f $ATLAS ]] || die "$ATLAS not found"

read -r WIDTH HEIGHT < <(im "$ATLAS" -format '%w %h\n' info:)
readonly SEPARATOR="#$(im "$ATLAS" -alpha off -format '%[hex:p{0,0}]' info:)"

# Collapsing the atlas to a single row (or column) averages each pixel line in one pass; only a
# line that is entirely separator averages back to the separator colour.
spans() {
    im "$ATLAS" -alpha off -scale "$1!" txt:- | awk -v sep="$SEPARATOR" -v min="$MIN_CARD" '
        NR > 1 {
            split($1, pos, ",")
            i = pos[1] + pos[2]
            separator[i] = ($3 == sep)
            if (i > last) last = i
        }
        END {
            start = -1
            for (i = 0; i <= last + 1; i++) {
                if (i <= last && !separator[i]) {
                    if (start < 0) start = i
                    continue
                }
                if (start >= 0 && i - start >= min) print start, i - start
                start = -1
            }
        }
    '
}

mapfile -t COLUMNS < <(spans "${WIDTH}x1")
mapfile -t ROWS < <(spans "1x${HEIGHT}")

(( ${#COLUMNS[@]} == ${#RANKS[@]} && ${#ROWS[@]} == ${#SUITS[@]} )) ||
    die "expected a ${#RANKS[@]}x${#SUITS[@]} grid, found ${#COLUMNS[@]}x${#ROWS[@]}"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

for r in "${!ROWS[@]}"; do
    read -r y h <<<"${ROWS[r]}"
    for c in "${!COLUMNS[@]}"; do
        read -r x w <<<"${COLUMNS[c]}"
        # Framing the cell in the separator colour gives -trim a known edge to eat back to, which
        # absorbs the atlas' one-pixel drift between rows.
        im "$ATLAS" -crop "${w}x${h}+${x}+${y}" +repage \
            -bordercolor "$SEPARATOR" -border 1 -fuzz 0 -trim +repage -strip \
            "$STAGE/${RANKS[c]}${SUITS[r]}.png"
    done
done

TARGET=$(im "$STAGE"/*.png -format '%wx%h\n' info: | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
read -r TARGET_W TARGET_H <<<"${TARGET/x/ }"

tolerance() {
    local t=$(( $1 * SIZE_TOLERANCE_PERCENT / 100 ))
    (( t > 2 )) || t=2
    echo "$t"
}
TOLERANCE_W=$(tolerance "$TARGET_W")
TOLERANCE_H=$(tolerance "$TARGET_H")

for card in "$STAGE"/*.png; do
    read -r w h < <(im "$card" -format '%w %h\n' info:)
    (( w == TARGET_W && h == TARGET_H )) && continue

    (( (w > TARGET_W ? w - TARGET_W : TARGET_W - w) <= TOLERANCE_W &&
       (h > TARGET_H ? h - TARGET_H : TARGET_H - h) <= TOLERANCE_H )) ||
        die "$(basename "$card" .png) came out ${w}x${h}, expected about $TARGET - check the atlas grid"

    echo "slice-cards: padding $(basename "$card" .png) from ${w}x${h} to $TARGET" >&2
    im "$card" -background "#$(im "$card" -alpha off -format '%[hex:p{0,0}]\n' info:)" \
        -gravity center -extent "$TARGET" -strip "$card"
done

mkdir -p "$OUT"
mv "$STAGE"/*.png "$OUT/"

echo "slice-cards: wrote $(( ${#ROWS[@]} * ${#COLUMNS[@]} )) cards at $TARGET to ${OUT#"$ROOT"/}"
