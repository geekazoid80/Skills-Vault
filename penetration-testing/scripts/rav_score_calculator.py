#!/usr/bin/env python3
"""Compute a simplified OSSTMM RAV (Risk Assessment Value) for one channel of
one engagement, from user-supplied counts. This is a defensible summary
metric for a single engagement, not a certified ISECOM OSSTMM audit.

Usage (interactive):
    python3 rav_score_calculator.py

Usage (non-interactive, all counts as flags):
    python3 rav_score_calculator.py \
        --porosity 12 --porosity-mitigated 7 \
        --controls-present 6 --controls-verified 4 \
        --vulnerabilities 2 --weaknesses 3 --concerns 1 --exposures 1 --anomalies 0

All counts are non-negative integers. See references/osstmm-model-and-scoping.md
for what each term means (porosity, the ten control classes, the five
limitation categories).
"""
import argparse

MAX_CONTROLS = 10


def compute_rav(porosity, porosity_mitigated, controls_present, controls_verified, limitations):
    """Return (rav_score, breakdown_dict). Score is clamped to [0, 100].

    porosity: total attack-surface access points identified
    porosity_mitigated: of those, how many are behind a verified control
    controls_present: how many of the 10 OSSTMM control classes exist at all (0-10)
    controls_verified: of those, how many were actually verified effective, not just claimed (0-10)
    limitations: dict with keys vulnerabilities, weaknesses, concerns, exposures, anomalies (counts)
    """
    if porosity < 0 or porosity_mitigated < 0 or porosity_mitigated > porosity:
        raise ValueError("porosity_mitigated must be between 0 and porosity")
    if not (0 <= controls_present <= MAX_CONTROLS) or not (0 <= controls_verified <= controls_present):
        raise ValueError("controls_present and controls_verified must be within 0..10, verified <= present")

    unmitigated_porosity = porosity - porosity_mitigated
    porosity_penalty = min(40, unmitigated_porosity * 4)

    control_credit = (controls_verified / MAX_CONTROLS) * 30 + ((controls_present - controls_verified) / MAX_CONTROLS) * 10

    # Limitations are weighted by severity: a confirmed vulnerability costs more
    # than an unconfirmed concern or an unexplained anomaly.
    weights = {"vulnerabilities": 8, "weaknesses": 5, "concerns": 3, "exposures": 4, "anomalies": 2}
    limitation_penalty = sum(weights.get(k, 0) * v for k, v in limitations.items())
    limitation_penalty = min(50, limitation_penalty)

    score = 100 - porosity_penalty + control_credit - limitation_penalty
    score = max(0, min(100, round(score, 1)))

    breakdown = {
        "starting_value": 100,
        "porosity_penalty": -porosity_penalty,
        "control_credit": round(control_credit, 1),
        "limitation_penalty": -limitation_penalty,
        "rav_score": score,
    }
    return score, breakdown


def band(score):
    if score >= 85:
        return "strong (low residual risk)"
    if score >= 65:
        return "moderate (manageable residual risk, address flagged limitations)"
    if score >= 40:
        return "weak (material residual risk, prioritise remediation)"
    return "critical (high residual risk, remediate before the next engagement)"


def prompt_int(label):
    while True:
        raw = input(f"{label}: ").strip()
        try:
            val = int(raw)
            if val < 0:
                raise ValueError
            return val
        except ValueError:
            print("  enter a non-negative integer")


def interactive():
    print("OSSTMM RAV score, simplified. One channel per run (e.g. Data Networks).\n")
    porosity = prompt_int("Porosity: total attack-surface access points identified")
    porosity_mitigated = prompt_int("Of those, how many sit behind a verified control")
    controls_present = prompt_int("How many of the 10 OSSTMM control classes exist at all (0-10)")
    controls_verified = prompt_int("Of those, how many were verified effective, not just claimed")
    print("\nLimitations found during this engagement:")
    limitations = {
        "vulnerabilities": prompt_int("  Vulnerabilities (confirmed exploitable flaws)"),
        "weaknesses": prompt_int("  Weaknesses (flawed control implementations)"),
        "concerns": prompt_int("  Concerns (potential flaws, not yet confirmed)"),
        "exposures": prompt_int("  Exposures (information disclosure)"),
        "anomalies": prompt_int("  Anomalies (unexplained items)"),
    }
    return porosity, porosity_mitigated, controls_present, controls_verified, limitations


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--porosity", type=int)
    parser.add_argument("--porosity-mitigated", type=int)
    parser.add_argument("--controls-present", type=int)
    parser.add_argument("--controls-verified", type=int)
    parser.add_argument("--vulnerabilities", type=int, default=0)
    parser.add_argument("--weaknesses", type=int, default=0)
    parser.add_argument("--concerns", type=int, default=0)
    parser.add_argument("--exposures", type=int, default=0)
    parser.add_argument("--anomalies", type=int, default=0)
    args = parser.parse_args()

    if args.porosity is None or args.porosity_mitigated is None or args.controls_present is None or args.controls_verified is None:
        porosity, porosity_mitigated, controls_present, controls_verified, limitations = interactive()
    else:
        porosity, porosity_mitigated = args.porosity, args.porosity_mitigated
        controls_present, controls_verified = args.controls_present, args.controls_verified
        limitations = {
            "vulnerabilities": args.vulnerabilities,
            "weaknesses": args.weaknesses,
            "concerns": args.concerns,
            "exposures": args.exposures,
            "anomalies": args.anomalies,
        }

    score, breakdown = compute_rav(porosity, porosity_mitigated, controls_present, controls_verified, limitations)

    print("\nRAV breakdown:")
    for k, v in breakdown.items():
        print(f"  {k}: {v}")
    print(f"\nRAV score: {score}/100 -- {band(score)}")


if __name__ == "__main__":
    main()
