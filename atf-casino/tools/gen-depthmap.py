#!/usr/bin/env python3
"""Generate common/media/depthmaps/DEPTH_atf_casino.png.

The sign at tile 0,0 is a wall overlay. Without a depth map the wall's own
depth geometry occludes it (the wall face sits nearer to the camera than a
sprite with no depth). This writes the same wall-face depth plane vanilla
uses for its wall-mounted ads (fitted from DEPTH_advertising_01.png tile 6,2,
the NE-leaning banner): depth = 1.3145*x + 0.6625*y - 47.81, where smaller
values are nearer to the camera. The game reads blue = depth, alpha 0 = no
data (zombie.tileDepth.TilesetDepthTexture.load).

pztool's --depthmaps flag is deliberately not used: it regenerates a
front-of-tile-volume depth every build, which would clobber this plane and
also wrongly occlude players standing on the sign's square.
"""

import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(REPO, "art", "atf_casino.png")
OUT = os.path.join(REPO, "common", "media", "depthmaps", "DEPTH_atf_casino.png")

TILE_W, TILE_H = 128, 256
PAD = 4


def plane(x, y):
    return 1.3145 * x + 0.6625 * y - 47.81


def main():
    art = Image.open(ART).convert("RGBA")
    tile = art.crop((0, 0, TILE_W, TILE_H))
    alpha = tile.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox is None:
        raise SystemExit("tile 0,0 of %s is empty" % ART)
    x1 = max(0, bbox[0] - PAD)
    y1 = max(0, bbox[1] - PAD)
    x2 = min(TILE_W, bbox[2] + PAD)
    y2 = min(TILE_H, bbox[3] + PAD)

    depth = Image.new("RGBA", art.size, (0, 0, 0, 0))
    px = depth.load()
    for y in range(y1, y2):
        for x in range(x1, x2):
            v = min(255, max(1, round(plane(x, y))))
            px[x, y] = (v, v, v, 255)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    depth.save(OUT)
    print("wrote %s (sign rect %d,%d-%d,%d)" % (OUT, x1, y1, x2, y2))


if __name__ == "__main__":
    main()
