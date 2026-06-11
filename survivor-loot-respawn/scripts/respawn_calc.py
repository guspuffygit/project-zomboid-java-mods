#!/usr/bin/env python3
"""
Solve for HoursTillMaxRespawnChance (H) given a target average respawn time.

The math mirrors HourlyRespawnRollHandler.computeChance + the once-per-hour roll
cadence driven by EveryHoursEvent, plus the quiet-period gate in
ContainerLootStateRepository.selectRolling.

Usage:
    python3 respawn_calc.py                                    # defaults
    python3 respawn_calc.py --target 96 --max 10 --quiet 48    # custom params
    python3 respawn_calc.py --H 96                             # forward direction (E[T] for a given H)
"""

import argparse


def per_roll_prob(h, H, min_c, max_c, steepness):
    """Per-roll probability (0..1) at hoursSinceLooted = h."""
    if H <= 0:
        return max_c / 100.0
    t = max(0.0, min(1.0, h / H))
    if steepness <= 1.0:
        curve = t
    else:
        curve = (steepness ** t - 1.0) / (steepness - 1.0)
    return (min_c + (max_c - min_c) * curve) / 100.0


def expected_hours(H, min_c, max_c, steepness, quiet, eps=1e-12, cap=1_000_000):
    """E[T] in game-hours from looting to respawn."""
    e_k = 0.0           # accumulates E[K]
    survive = 1.0       # P(K >= current trial)
    j = 0
    while survive > eps and j < cap:
        e_k += survive
        p = per_roll_prob(quiet + j, H, min_c, max_c, steepness)
        survive *= (1.0 - p)
        j += 1
    return quiet + e_k - 1.0


def solve_H(target, min_c, max_c, steepness, quiet,
            lo=1.0, hi=1_000_000.0, iters=80):
    """Binary search for H such that E[T] == target. E[T] is monotonic in H."""
    if expected_hours(hi, min_c, max_c, steepness, quiet) < target:
        raise ValueError(
            f"Target E[T]={target}h is unreachable with min={min_c}, max={max_c}, "
            f"steepness={steepness}, quiet={quiet}. Even H={hi:.0f} only gives "
            f"E[T]={expected_hours(hi, min_c, max_c, steepness, quiet):.2f}h. "
            "Lower the cap (MaxRespawnChance) or raise the quiet period."
        )
    for _ in range(iters):
        mid = 0.5 * (lo + hi)
        if expected_hours(mid, min_c, max_c, steepness, quiet) < target:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target",    type=float, default=96.0,  help="Desired average respawn time, hours (default: 96)")
    p.add_argument("--min",       dest="min_c",     type=float, default=0,    help="MinRespawnChance %% (default: 0)")
    p.add_argument("--max",       dest="max_c",     type=float, default=100,  help="MaxRespawnChance %% (default: 100)")
    p.add_argument("--steepness", type=float, default=1.05, help="CurveSteepness (default: 1.05)")
    p.add_argument("--quiet",     type=float, default=0,    help="ContainerQuietPeriodHours (default: 0)")
    p.add_argument("--H",         type=float, default=None,
                   help="If set, just print E[T] for this H instead of solving for H.")
    args = p.parse_args()

    if args.H is not None:
        e = expected_hours(args.H, args.min_c, args.max_c, args.steepness, args.quiet)
        print(f"H={args.H}  min={args.min_c}%  max={args.max_c}%  steepness={args.steepness}  quiet={args.quiet}h")
        print(f"  -> average respawn time E[T] = {e:.3f}h")
        return

    H = solve_H(args.target, args.min_c, args.max_c, args.steepness, args.quiet)
    achieved = expected_hours(H, args.min_c, args.max_c, args.steepness, args.quiet)
    print(f"min={args.min_c}%  max={args.max_c}%  steepness={args.steepness}  quiet={args.quiet}h  target E[T]={args.target}h")
    print(f"  -> HoursTillMaxRespawnChance = {H:.2f}  (achieves E[T] = {achieved:.4f}h)")
    print()
    print("Sanity table (E[T] as a function of H, same other params):")
    table_Hs = sorted({48, 96, 144, 192, 240, 288, int(round(H))})
    for h in table_Hs:
        e = expected_hours(h, args.min_c, args.max_c, args.steepness, args.quiet)
        marker = "  <-- solved" if h == int(round(H)) else ""
        print(f"  H={h:>6}  ->  E[T] = {e:7.3f}h{marker}")


if __name__ == "__main__":
    main()
