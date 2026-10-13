"""The rev counter needle: XorNeedle draws every dial position (0-151) with
exactly the pixels saved from a reference build (golden data), drawing it a
second time restores the screen, and drawing all the positions stays within
the time budget.

Usage:
  python tests/test_needle.py golden    save golden data (reference build)
  python tests/test_needle.py           compare
"""
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402

GOLDEN = Path(__file__).resolve().parent / 'needle_golden.json'
POSITIONS = 152
BUDGET = 340_000                        # T-states for all positions (no contention)


def draw_all(z):
    """For each position: the XORed screen bytes {address: mask}, whether a
    second draw restored the screen, and the total T-states of the first draws."""
    rng = random.Random(5)
    screen = [rng.randrange(256) for _ in range(6144)]
    out, restored, total = [], True, 0
    for pos in range(POSITIONS):
        z.mem[0x4000:0x5800] = screen
        total += z.call('XorNeedle', a=pos)
        out.append({str(0x4000 + i): z.mem[0x4000 + i] ^ screen[i]
                    for i in range(6144) if z.mem[0x4000 + i] != screen[i]})
        z.call('XorNeedle', a=pos)
        restored &= list(z.mem[0x4000:0x5800]) == screen
    return out, restored, total


def main():
    z = Z80()
    drawn, restored, total = draw_all(z)
    if len(sys.argv) > 1 and sys.argv[1] == 'golden':
        GOLDEN.write_text(json.dumps(drawn))
        print(f'saved {POSITIONS} positions, {total} T')
        return 0
    gold = json.loads(GOLDEN.read_text())
    fails = [p for p in range(POSITIONS) if drawn[p] != gold[p]]
    for p in fails[:3]:
        print(f'position {p}: Z80 {sorted(drawn[p].items())[:6]} golden {sorted(gold[p].items())[:6]}')
    ok = not fails and restored and total <= BUDGET
    print(f'needle: {len(fails)}/{POSITIONS} positions differ, second draw restores: {restored}, '
          f'{total} T (budget {BUDGET}): {"OK" if ok else "FAIL"}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
