"""Regenerate the literal data files in src/ (see tools/srcdata.py).

The build only assembles src/; run this after changing the artwork in
assets/ or a generator. The data imported from the C64 Revs+ tape and the
annotated BBC source (track files, projection and object tables, driver
names, zero page layout, track code constants) comes out the same every
time: tests/test_srcdata.py checks that src/ matches.

Usage: python tools/gen_src.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_c64data  # noqa: E402
import gen_cockpit  # noqa: E402
import gen_objects  # noqa: E402
import gen_tables  # noqa: E402
import gen_text  # noqa: E402
import gen_trackcode  # noqa: E402
import gen_vars  # noqa: E402
import loading_screen  # noqa: E402

GENERATORS = [gen_c64data, gen_tables, gen_cockpit, gen_vars, gen_objects, gen_text, gen_trackcode,
              loading_screen]


def main():
    for g in GENERATORS:
        g.main()


if __name__ == '__main__':
    main()
