#!/usr/bin/env python3
"""Evaluate exact, page-anchored later-reference mentions on fixed local PDFs."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def score_pages(expected: list[int], actual: list[int]) -> tuple[int, int, int]:
    """A page may contain multiple distinct citations; keep multiplicity."""
    truth = Counter(expected)
    found = Counter(actual)
    true_positives = sum((truth & found).values())
    return (
        true_positives,
        sum((found - truth).values()),
        sum((truth - found).values()),
    )


def evaluate_case(
    app: Path, pdf_dir: Path, labels_dir: Path, case: dict, graph_mode: bool = False
) -> tuple[int, int, int, int, int]:
    filename = case["pdfFilename"]
    if Path(filename).name != filename or not filename.lower().endswith(".pdf"):
        raise ValueError(f"Unsafe PDF filename in labels: {filename!r}")
    pdf = pdf_dir / filename
    expected_hash = case["document"].removeprefix("sha256:")
    if not case["document"].startswith("sha256:") or sha256(pdf) != expected_hash:
        raise ValueError(f"PDF fingerprint does not match labels: {pdf}")

    if graph_mode:
        reference_labels_name = case["referenceLabelsFilename"]
        if Path(reference_labels_name).name != reference_labels_name:
            raise ValueError(f"Unsafe reference-label filename: {reference_labels_name!r}")
        command = [
            str(app), "--probe-graph", str(pdf),
            str(labels_dir / reference_labels_name), "--json",
        ]
    else:
        command = [
            str(app), "--probe-mentions", str(pdf), case["kind"],
            case["number"], str(case["definingPage"]), "--json",
        ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=120, check=False)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Probe failed for {filename}: {completed.stderr.strip()} {completed.stdout.strip()}"
        )
    report = json.loads(completed.stdout)
    if graph_mode:
        if report["documentFingerprint"] != expected_hash:
            raise ValueError(f"Graph fingerprint does not match labels: {pdf}")
        records = [
            record for record in report["records"]
            if record["definition"]["reference"] == {
                "kind": case["kind"], "number": case["number"]
            }
        ]
        if len(records) != 1:
            raise ValueError(f"Graph has {len(records)} nodes for {case['kind']} {case['number']}")
        report = records[0]["result"]
    mentions = report["mentions"]
    actual_pages = [mention["pageIndex"] + 1 for mention in mentions]
    for mention in mentions:
        region = mention["region"]
        if not (0 <= region["x"] <= 1 and 0 <= region["y"] <= 1
                and 0 < region["width"] <= 1 and 0 < region["height"] <= 1):
            raise ValueError(f"Invalid anchor for {filename}: {region}")
    tp, fp, fn = score_pages(case["expectedPages"], actual_pages)
    return tp, fp, fn, report["unresolvedMatches"], report["pagesWithoutText"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Built Cauchy executable")
    parser.add_argument("--pdf-dir", required=True, type=Path, help="Directory holding labelled PDFs")
    parser.add_argument("--graph", action="store_true", help="Evaluate the one-pass graph builder")
    parser.add_argument(
        "--labels", type=Path,
        default=Path(__file__).parent / "corpus/reference-mentions.ground-truth.json",
    )
    args = parser.parse_args()
    labels = json.loads(args.labels.read_text())
    if labels.get("schemaVersion") != 1:
        raise ValueError("Unsupported mention-label schema")

    totals = [0, 0, 0, 0, 0]
    print("Reference | Expected pages | TP / FP / FN | Unlocated | Pages without text")
    print("----------|----------------|--------------|-----------|-------------------")
    for case in labels["cases"]:
        result = evaluate_case(args.app, args.pdf_dir, args.labels.parent, case, args.graph)
        totals = [a + b for a, b in zip(totals, result)]
        expected = ", ".join(map(str, case["expectedPages"])) or "none"
        title = f"{case['kind']} {case['number']}"
        print(f"{title} | {expected} | {result[0]} / {result[1]} / {result[2]} | "
              f"{result[3]} | {result[4]}")
    tp, fp, fn, unlocated, no_text = totals
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    print(f"\n{len(labels['cases'])} cases: TP {tp}, FP {fp}, FN {fn}; "
          f"precision {precision:.1%}, recall {recall:.1%}; "
          f"{unlocated} unlocated matches, {no_text} page(s) without text.")
    if labels.get("split") == "holdout":
        print("Predeclared holdout labels. Preserve this first result before any tuning on these cases.")
    else:
        print("Development cases only; these references were inspected while tuning the finder.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
