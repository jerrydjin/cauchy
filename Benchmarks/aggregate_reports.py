#!/usr/bin/env python3
"""Summarize labelled Cauchy report.json files without hiding document failures."""

import argparse
import json
import math
from pathlib import Path


BASELINES = (
    "All syntactic mentions",
    "Declaration heuristic",
)


def systems_for_mode(mode: str) -> tuple[str, ...]:
    primary = "Source-only extractor" if mode == "source-only" else "Cauchy production extractor"
    return (primary, *BASELINES)


def percent(numerator: int, denominator: int, *, empty_value: float = 1.0) -> float:
    return numerator / denominator if denominator else empty_value


def metrics(tp: int, fp: int, fn: int) -> tuple[float, float, float]:
    precision = percent(tp, tp + fp)
    recall = percent(tp, tp + fn)
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return precision, recall, f1


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    position = fraction * (len(values) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def load_report(path: Path) -> dict:
    report_path = path / "report.json" if path.is_dir() else path
    report = json.loads(report_path.read_text(encoding="utf-8"))
    summary = report["summary"]
    pages = report["pages"]
    if not summary.get("groundTruthPath"):
        raise ValueError(f"{report_path}: not a labelled benchmark")
    if len(pages) != summary["sampledPages"]:
        raise ValueError(f"{report_path}: page count does not match summary")
    if any(page.get("expectedReferences") is None for page in pages):
        raise ValueError(f"{report_path}: unlabelled page in report")
    systems = {item["system"]: item for item in summary["evaluations"]}
    expected_systems = systems_for_mode(summary.get("indexingMode", "on-device model"))
    if set(systems) != set(expected_systems):
        raise ValueError(f"{report_path}: unexpected evaluation systems")
    report["_path"] = str(report_path)
    return report


def summarize(reports: list[dict]) -> dict:
    if not reports:
        raise ValueError("at least one labelled report is required")
    documents = [report["summary"]["pdfPath"] for report in reports]
    if len(set(documents)) != len(documents):
        raise ValueError("duplicate document in corpus reports")
    modes = {report["summary"].get("indexingMode", "on-device model") for report in reports}
    if len(modes) != 1:
        raise ValueError("cannot aggregate different indexing modes")
    mode = modes.pop()
    systems = systems_for_mode(mode)

    pages = [page for report in reports for page in report["pages"]]
    aggregate = {}
    for system in systems:
        evaluations = [
            next(item for item in report["summary"]["evaluations"] if item["system"] == system)
            for report in reports
        ]
        tp = sum(item["truePositives"] for item in evaluations)
        fp = sum(item["falsePositives"] for item in evaluations)
        fn = sum(item["falseNegatives"] for item in evaluations)
        precision, recall, f1 = metrics(tp, fp, fn)
        aggregate[system] = {
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "correctAbstentions": sum(item["correctAbstentions"] for item in evaluations),
            "negativePages": sum(item["negativePages"] for item in evaluations),
        }

    durations = [page["seconds"] for page in pages if page["succeeded"]]
    return {
        "documents": len(reports),
        "indexingMode": mode,
        "pages": len(pages),
        "failedPages": sum(not page["succeeded"] for page in pages),
        "expectedReferences": sum(len(page["expectedReferences"]) for page in pages),
        "modelAccepted": sum(page["modelAcceptedCount"] for page in pages),
        "sourceFallbacks": sum(page["sourceFallbackCount"] for page in pages),
        "contextOverflows": sum(
            page["disposition"] == "context_overflow_source_fallback" for page in pages
        ),
        "medianSeconds": percentile(durations, 0.5),
        "p95Seconds": percentile(durations, 0.95),
        "maxSeconds": max(durations, default=0.0),
        "systems": aggregate,
    }


def format_percent(value: float) -> str:
    return f"{value * 100:.1f}%"


def markdown(reports: list[dict]) -> str:
    total = summarize(reports)
    systems = systems_for_mode(total["indexingMode"])
    lines = [
        f"# Cauchy labelled reference-index corpus ({total['indexingMode']})",
        "",
        f"{total['documents']} documents; {total['pages']} labelled pages; "
        f"{total['expectedReferences']} introduced references; "
        f"{total['failedPages']} extraction failures.",
        "",
        "| Document | Pages | Labels | Extractor P / R / F1 | Abstentions | Source fallbacks | Context overflows |",
        "|----------|------:|-------:|------------------------|------------:|-----------------:|------------------:|",
    ]
    for report in reports:
        summary = report["summary"]
        production = next(
            item for item in summary["evaluations"] if item["system"] == systems[0]
        )
        overflow = sum(
            page["disposition"] == "context_overflow_source_fallback"
            for page in report["pages"]
        )
        score = " / ".join(format_percent(production[key]) for key in ("precision", "recall", "f1"))
        lines.append(
            f"| {Path(summary['pdfPath']).stem} | {summary['sampledPages']} | "
            f"{production['truePositives'] + production['falseNegatives']} | {score} | "
            f"{production['correctAbstentions']}/{production['negativePages']} | "
            f"{summary['totalSourceFallbacks']} | {overflow} |"
        )

    lines.extend([
        "",
        "Micro-averaged over reference instances (not an average of per-document percentages):",
        "",
        "| System | Precision | Recall | F1 | TP | FP | FN | Correct abstentions |",
        "|--------|----------:|-------:|---:|---:|---:|---:|--------------------:|",
    ])
    for system in systems:
        row = total["systems"][system]
        lines.append(
            f"| {system} | {format_percent(row['precision'])} | "
            f"{format_percent(row['recall'])} | {format_percent(row['f1'])} | "
            f"{row['tp']} | {row['fp']} | {row['fn']} | "
            f"{row['correctAbstentions']}/{row['negativePages']} |"
        )
    lines.extend([
        "",
        f"Accepted model transcriptions: {total['modelAccepted']}; "
        f"source fallbacks: {total['sourceFallbacks']}; "
        f"context-overflow degradations: {total['contextOverflows']}.",
        f"End-to-end per-page latency including skipped pages: median "
        f"{total['medianSeconds']:.1f}s; interpolated p95 {total['p95Seconds']:.1f}s; "
        f"maximum {total['maxSeconds']:.1f}s.",
        "",
        "These development slices were inspected and tuned during implementation. "
        "They are not a held-out estimate of generalization.",
    ])
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="report.json files or directories")
    args = parser.parse_args()
    print(markdown([load_report(path) for path in args.reports]), end="")


if __name__ == "__main__":
    main()
