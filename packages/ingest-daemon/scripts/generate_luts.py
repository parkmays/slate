#!/usr/bin/env python3
"""Generate 33-point LUTs for SLATE proxy viewing transforms."""

from __future__ import annotations

import math
from pathlib import Path
from typing import Callable

SIZE = 33

# Blackmagic Film Gen 5 constants.
BMD_A = 0.08692876065491224
BMD_B = 0.005494072432257808
BMD_C = 0.6835710065
BMD_D = 0.08


def clamp01(value: float) -> float:
    return min(1.0, max(0.0, value))


def rec709_oetf(linear: float) -> float:
    linear = max(0.0, linear)
    if linear <= 0.018:
        return 4.5 * linear
    return 1.099 * (linear ** 0.45) - 0.099


def arri_logc3_to_linear(x: float) -> float:
    if x > 0.010591:
        return (10.0 ** ((x - 0.385537) / 0.247190) - 0.052272) / 5.555556
    return (x - 0.092809) / 5.367655


def bmd_film_gen5_to_linear(x: float) -> float:
    if x >= BMD_D:
        return math.exp((x - BMD_C) / BMD_A) - BMD_B
    return -(math.exp(-(x - BMD_C) / BMD_A) - BMD_B)


def red_log3g10_to_linear(x: float) -> float:
    if x >= 0.0:
        return (10.0 ** (x / 0.224282) - 1.0) / 155.975327
    return x / 9.0


def write_lut(path: Path, decode: Callable[[float], float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("LUT_3D_SIZE 33\n\n")
        for b in range(SIZE):
            zb = b / (SIZE - 1)
            for g in range(SIZE):
                yg = g / (SIZE - 1)
                for r in range(SIZE):
                    xr = r / (SIZE - 1)
                    rr = clamp01(rec709_oetf(decode(xr)))
                    gg = clamp01(rec709_oetf(decode(yg)))
                    bb = clamp01(rec709_oetf(decode(zb)))
                    handle.write(f"{rr:.8f} {gg:.8f} {bb:.8f}\n")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    output_dir = root / "Resources" / "LUTs"
    write_lut(output_dir / "arri_logc3_rec709.cube", arri_logc3_to_linear)
    write_lut(output_dir / "bm_film_gen5_rec709.cube", bmd_film_gen5_to_linear)
    write_lut(output_dir / "red_ipp2_rec709.cube", red_log3g10_to_linear)
    print(f"Generated LUTs in {output_dir}")


if __name__ == "__main__":
    main()
