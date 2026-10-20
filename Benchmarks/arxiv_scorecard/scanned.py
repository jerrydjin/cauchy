"""Score older scanned mathematics separately from the arXiv dev set.

The PDFs are downloaded into the local cache and are not committed. The
checks are the scorecard's existing reader port: PyMuPDF text extraction,
the main-profile reference detector, the source-fallback statement index,
and the section locator. Nothing here runs OCR or changes the reader.

A paper passes when the text layer is present, at least eight in-scope
references are recovered and at least 90% of them are in the statement
index, and every listed section question lands on the page that prints
the heading. The report is this set's own score. It is not a release gate.

    python3 Benchmarks/arxiv_scorecard/run.py --scanned
"""

from __future__ import annotations

import json
from pathlib import Path

from cauchy_logic import (
    build_statement_index,
    heading_line,
    is_likely_table_of_contents,
    locate,
    logical_lines,
    structural_query,
)
from cauchy_logic import _explicit_section_number
from ground_truth import IN_SCOPE
from run import CACHE, _get
from score import PASS_MIN_REFERENCES, PASS_MIN_RESOLUTION, _inside, _page_maps, make_structure

ROOT = Path(__file__).resolve().parent
IDS_PATH = ROOT / "scanned_ids.json"
JSON_OUT = ROOT / "scanned_scorecard.json"
MD_OUT = ROOT.parent / "results" / "2026-10-20-scanned-math-scorecard.md"

# A prose line in the two-column heuristic needs 40 letters. A page under
# that has no usable text layer.
_BLANK_LETTERS = 40
_BLANK_PAGE_FRACTION = 0.8

_MODE_NO_TEXT = "no text layer"
_MODE_REFERENCES = "broken reference detection"
_MODE_SECTION = "wrong section resolution"


def load_ids(path: Path | None = None) -> dict:
    return json.loads((path or IDS_PATH).read_text())


def counts_toward_release_gate(report: dict) -> bool:
    return bool(report.get("counts_toward_release_gate"))


def _letters(text: str) -> int:
    return sum(character.isalpha() for character in text)


def text_layer(extracted: dict) -> dict:
    pages = extracted["pages"]
    counts = [_letters(page["text"]) for page in pages]
    blank = sum(1 for count in counts if count < _BLANK_LETTERS)
    median = sorted(counts)[len(counts) // 2] if counts else 0
    missing = bool(pages) and (
        median < _BLANK_LETTERS or blank / len(pages) >= _BLANK_PAGE_FRACTION
    )
    cover_only = missing and any(
        "digital copy of a book" in page["text"].lower() for page in pages
    )
    return {
        "pages": len(pages),
        "blank_pages": blank,
        "median_letters": median,
        "missing": missing,
        "cover_note_only": cover_only,
    }


def _reference_report(pages: list[dict]) -> dict:
    matches, cites, prepared = _page_maps(pages, "main")
    index = build_statement_index(prepared, "main")
    hits = []
    citation_detections = 0
    for page in pages:
        page_matches = matches.get(page["page_index"], [])
        for match in page_matches:
            if _inside(cites.get(page["page_index"], []), match.start, match.end):
                citation_detections += 1
            if match.kind not in IN_SCOPE:
                continue
            hits.append(match)
    resolved = sum(1 for match in hits if index.lookup(match.kind, match.number) is not None)
    rate = 1.0 if not hits else resolved / len(hits)
    samples = []
    for page in pages:
        for match in matches.get(page["page_index"], []):
            if match.kind not in IN_SCOPE:
                continue
            samples.append(f"p.{page['page_index'] + 1} {match.kind} ({match.number})")
            if len(samples) == 8:
                break
        if len(samples) == 8:
            break
    ok = (
        len(hits) >= PASS_MIN_REFERENCES
        and rate >= PASS_MIN_RESOLUTION
        and citation_detections == 0
    )
    return {
        "ok": ok,
        "in_scope": len(hits),
        "resolved": resolved,
        "resolution_rate": round(rate, 4),
        "indexed": len(index),
        "citation_detections": citation_detections,
        "samples": samples,
    }


def _numbered_headings(pages: list[dict]) -> list[dict]:
    found = []
    seen: set[str] = set()
    for page in pages:
        if is_likely_table_of_contents(page["text"]):
            continue
        for raw in logical_lines(page["text"], page.get("line_bold"), page.get("line_italic")):
            heading = heading_line(raw.strip())
            if heading is None:
                continue
            number = _explicit_section_number(heading)
            if number is None or number in seen:
                continue
            if not number.replace(".", "").isdigit():
                continue
            seen.add(number)
            found.append({"number": number, "title": heading[:80], "page": page["page_index"] + 1})
    return found


def _section_report(extracted: dict, sections: list[dict]) -> dict:
    structure = make_structure(extracted)
    expected = sections or _numbered_headings(extracted["pages"])
    probed = []
    for section in expected:
        number = str(section["number"])
        query = structural_query(f"what is section {number} about")
        found = None if query is None else locate(query, structure)
        predicted = None if found is None else found.start_page + 1
        labeled = int(section["page"])
        probed.append({
            "number": number,
            "title": section.get("title") or "",
            "expected_page": labeled,
            "predicted_page": predicted,
            "label": None if found is None else found.label,
            "ok": predicted == labeled,
        })
    if not probed:
        return {
            "probed": [],
            "ok": False,
            "reason": "no numbered section heading located",
        }
    ok = all(item["ok"] for item in probed)
    return {
        "probed": probed,
        "ok": ok,
        "reason": None if ok else "a section question missed its heading page",
    }


def classify_extraction(extracted: dict, sections: list[dict] | None = None) -> dict:
    """Run the existing reader checks on one extracted PDF.

    ``sections`` are 1-based PDF pages taken from the book's contents, not
    from the locator. An empty list means the source has no numbered
    sections to compare, so the check uses whatever heading the reader
    itself accepts.
    """
    layer = text_layer(extracted)
    references = _reference_report(extracted["pages"])
    section = _section_report(extracted, sections or [])
    modes: list[str] = []
    if layer["missing"]:
        modes.append(_MODE_NO_TEXT)
    else:
        if not references["ok"]:
            modes.append(_MODE_REFERENCES)
        if not section["ok"]:
            modes.append(_MODE_SECTION)
    return {
        "passes": not modes,
        "failure_modes": modes,
        "text_layer": layer,
        "references": references,
        "sections": section,
    }


def _cache_pdf(record: dict) -> Path:
    path = CACHE / "scanned" / f"{record['id']}.pdf"
    if path.exists() and path.stat().st_size > 1000:
        return path
    print(f"download {record['id']}", flush=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_get(record["source_url"], timeout=120))
    return path


def score_record(record: dict) -> dict:
    from pdf_extract import extract_pdf

    extracted = extract_pdf(str(_cache_pdf(record)))
    card = classify_extraction(extracted, record.get("sections") or [])
    return {
        "id": record["id"],
        "title": record.get("title"),
        "author": record.get("author"),
        "year": record.get("year"),
        "source_url": record["source_url"],
        "source_page": record.get("source_page"),
        "license": record.get("license"),
        "page_count": extracted["page_count"],
        **card,
    }


def _mode_list(modes: list[str]) -> str:
    return ", ".join(modes) if modes else "none"


def write_markdown(report: dict, path: Path | None = None) -> None:
    papers = report["papers"]
    lines = [
        "# Scanned mathematics scorecard",
        "",
        f"**{report['passes']} of {report['total']} pass.**",
        "",
        "This is the scanned set's own score. It does not count toward a release gate, and it is not part of the arXiv dev headline.",
        "",
        "The checks are the existing reader port. A page with fewer than 40 letters has no text layer. A paper has no text layer when the median page is blank or at least 80% of its pages are blank. Otherwise a paper needs at least 8 theorem, lemma, definition, equation, or section references, at least 90% of those references in the source-fallback index, and every section question on the page that prints the heading. No OCR was run, and the reader was not changed.",
        "",
        "| Paper | Year | Text layer | Pass | Failure modes |",
        "|---|---|---|---|---|",
    ]
    for paper in papers:
        layer = paper["text_layer"]
        layer_cell = (
            f"missing ({layer['blank_pages']}/{layer['pages']} pages blank)"
            if layer["missing"]
            else f"present (median {layer['median_letters']} letters/page)"
        )
        lines.append(
            f"| {paper['author']} | {paper['year']} | {layer_cell} | "
            f"{'pass' if paper['passes'] else 'fail'} | {_mode_list(paper['failure_modes'])} |"
        )
    lines.extend(["", "## Per paper", ""])
    for paper in papers:
        references = paper["references"]
        lines.append(f"### {paper['id']} — {paper['title']}")
        lines.append("")
        lines.append(f"{paper['author']}, {paper['year']}. {paper['license']}")
        lines.append(f"Source: {paper['source_url']}")
        if paper.get("source_page"):
            lines.append(f"Record: {paper['source_page']}")
        layer = paper["text_layer"]
        if references["in_scope"] == 0:
            recovered = "In-scope references recovered: 0."
        else:
            recovered = (
                f"In-scope references {references['resolved']}/{references['in_scope']} "
                f"in the index ({references['resolution_rate']:.0%})."
            )
        cover = ""
        if layer.get("cover_note_only"):
            cover = " The only page with letters is the digitizer's cover note."
        lines.append(
            f"Text layer: median {layer['median_letters']} letters/page, "
            f"{layer['blank_pages']}/{layer['pages']} pages under 40 letters.{cover} "
            f"{recovered} Citation emissions {references['citation_detections']}."
        )
        if references["samples"]:
            lines.append("References the detector emitted: " + "; ".join(references["samples"]) + ".")
        if paper["sections"]["probed"]:
            lines.append("Section questions:")
            for item in paper["sections"]["probed"]:
                mark = "ok" if item["ok"] else "miss"
                predicted = "none" if item["predicted_page"] is None else f"p.{item['predicted_page']}"
                lines.append(
                    f"- {mark} section {item['number']} ({item['title']}) "
                    f"heading on p.{item['expected_page']}, locator {predicted}"
                )
        elif paper["sections"].get("reason"):
            lines.append(f"Section questions: {paper['sections']['reason']}.")
        lines.append(f"Failure modes: {_mode_list(paper['failure_modes'])}.")
        lines.append("")
    destination = path or MD_OUT
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines) + "\n")


def run_scanned(ids_path: Path | None = None, json_out: Path | None = None, markdown_out: Path | None = None) -> dict:
    payload = load_ids(ids_path)
    papers = [score_record(record) for record in payload["papers"]]
    report = {
        "set": "scanned",
        "counts_toward_release_gate": False,
        "passes": sum(1 for paper in papers if paper["passes"]),
        "total": len(papers),
        "papers": papers,
    }
    destination = json_out or JSON_OUT
    destination.write_text(json.dumps(report, indent=2) + "\n")
    write_markdown(report, markdown_out or MD_OUT)
    print(
        f"SCANNED {report['passes']}/{report['total']} "
        f"release_gate={counts_toward_release_gate(report)}",
        flush=True,
    )
    for paper in papers:
        print(f"  {paper['id']} pass={paper['passes']} modes={paper['failure_modes']}", flush=True)
    return report


if __name__ == "__main__":
    run_scanned()
