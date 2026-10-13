"""The loading screen: assets/loading/revs.png (the user's artwork, 256x192,
Spectrum colours, from the user's ZX version) as SCREEN$, without
resampling. Encoded as the user's tools/loading_screen.py: in the four
flag-edge cells with three colours the two most frequent stay and 13
isolated corner pixels become blue (the approved conversion)."""
from collections import Counter
from pathlib import Path

from PIL import Image

SOURCE = Path(__file__).resolve().parents[1] / 'assets/loading/revs.png'
PALETTE = [(255 if c & 2 else 0, 255 if c & 4 else 0, 255 if c & 1 else 0) for c in range(8)]


def screen_bytes():
    image = Image.open(SOURCE).convert('RGB')
    assert image.size == (256, 192), 'the loading screen must be 256x192'
    data = bytearray(6912)
    for row in range(24):
        for col in range(32):
            pixels = [PALETTE.index(image.getpixel((col * 8 + x, row * 8 + y)))
                      for y in range(8) for x in range(8)]
            colours = sorted(set(pixels))
            if len(colours) > 2:
                colours = [c for c, _ in Counter(pixels).most_common(2)]
                pixels = [c if c in colours else
                          min(colours, key=lambda d: sum((a - b) ** 2 for a, b in zip(PALETTE[c], PALETTE[d])))
                          for c in pixels]
            paper = 1 if 1 in colours else colours[0]          # blue paper where there is blue
            ink = next((c for c in colours if c != paper), paper)
            data[6144 + row * 32 + col] = 64 | paper << 3 | ink     # bright
            for dy in range(8):
                y = row * 8 + dy
                address = (y & 192) << 5 | (y & 7) << 8 | (y & 56) << 2 | col
                data[address] = sum((pixels[dy * 8 + x] == ink) << (7 - x) for x in range(8))
    return bytes(data)


def main():
    """src/gfx/loading.scr: the SCREEN$ for the game tape."""
    import srcdata
    srcdata.write_bin('gfx/loading.scr', screen_bytes())

if __name__ == '__main__':
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
