"""The literal data in src/ is what the import tools make of the originals:
tools/gen_src.py runs into a temporary directory (the track files and the
projection, object and text tables from the C64 Revs+ tape, the zero page
layout and scaffold measurements from the annotated BBC source, the track
code constants from the C64 track code, the computed tables, the graphics
in src/gfx from the artwork in assets/) and every file must equal its copy
in src/."""
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import gen_src  # noqa: E402


def main():
    with tempfile.TemporaryDirectory() as tmp:
        os.environ['REVS_SRC_OUT'] = tmp
        try:
            gen_src.main()
        finally:
            del os.environ['REVS_SRC_OUT']
        files = sorted(f.relative_to(tmp).as_posix() for f in Path(tmp).rglob('*') if f.is_file())
        bad = [f for f in files if (Path(tmp) / f).read_bytes() != (ROOT / 'src' / f).read_bytes()]
        assert files and not bad, f'src/ differs from the import tools: {bad}'
        print(f'srcdata: {len(files)} data files in src/ match their sources')


if __name__ == '__main__':
    main()
