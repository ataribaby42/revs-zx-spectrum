"""Literal data files in src/ (the build's only input besides the code).

The import tools (gen_*.py, run together by tools/gen_src.py) write them:
data taken from the C64 Revs+ tape and the annotated BBC source, computed
tables, and in src/gfx the graphics converted from the artwork in assets/.
The build never runs them. tests/test_srcdata.py runs them into a temporary directory
(REVS_SRC_OUT) and compares the result with src/.
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def out_dir():
    path = Path(os.environ.get('REVS_SRC_OUT', ROOT / 'src'))
    path.mkdir(parents=True, exist_ok=True)
    return path


def db_lines(data, per_line=16):
    return ['        db ' + ', '.join(f'${b:02X}' for b in data[i:i + per_line])
            for i in range(0, len(data), per_line)]


def write(name, lines):
    """src/name from a list of lines (CRLF, as the hand-written sources)."""
    path = out_dir() / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', newline='\r\n')


def write_db(name, header, data, per_line=16):
    """src/name: header comment lines, then data as db lines."""
    write(name, [f'; {h}' if h else ';' for h in header] + [''] + db_lines(data, per_line))


# the six tracks (C64 track selector order) and their file name keys
TRACK_KEYS = {'Brands Hatch': 'brandshatch', 'Donington Park': 'doningtonpark',
              'Nurburgring': 'nurburgring', 'Oulton Park': 'oultonpark',
              'Silverstone': 'silverstone', 'Snetterton': 'snetterton'}


def write_bin(name, data):
    """src/name as binary data (the graphics in src/gfx)."""
    path = out_dir() / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(data))
