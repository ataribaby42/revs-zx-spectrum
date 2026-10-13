"""Import data used verbatim from the C64 Revs+ tape into src/.

Writes:
  src/trackdata_<track>.asm  the 2 KiB C64 track file of each of the six
                             tracks (C64 $5300-$5AFF, the track slot TRACK)
  src/projdata.asm           projection tables in the page order of
                             src/proj.asm
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

from c64_image import TRACKS, main_image  # noqa: E402
import srcdata  # noqa: E402

PROJ_PAGES = [0xBC00, 0xBD00, 0xBE00, 0xCB00, 0xCA00, 0xBF00, 0xC800, 0xC900]


def main():
    for track in TRACKS:
        data = bytes(main_image(track)[0x5300:0x5B00])
        lines = [f'; {track}: the C64 track file (C64 $5300-$5AFF, the track slot TRACK).',
                 '; Imported from the C64 Revs+ tape by tools/gen_c64data.py; track data',
                 '; at the offsets of src/vars.asm (the 6502 track code in it is not used',
                 '; here: the extra tracks have their Z80 track code, src/trackcode.asm).']
        for page in range(8):
            lines += ['', f'; +${page * 0x100:03X}'] + srcdata.db_lines(data[page * 0x100:page * 0x100 + 0x100])
        srcdata.write(f'trackdata_{srcdata.TRACK_KEYS[track]}.asm', lines)
    m = main_image('Silverstone')
    proj = bytearray()
    for p in PROJ_PAGES:
        proj += m[p:p + 256]
    proj += m[0xC000:0xC800]
    proj += m[0x6640:0x66C0]
    srcdata.write_db('projdata.asm', [
        'Projection tables of the C64 code, in the page order of src/proj.asm:',
        'pages ' + ', '.join(f'${p:04X}' for p in PROJ_PAGES) + ', then $C000-$C7FF',
        'and $6640-$66BF. Imported by tools/gen_c64data.py.'], proj)


if __name__ == '__main__':
    main()
