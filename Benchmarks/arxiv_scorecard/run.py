"""Download the fixed arXiv set and write a per-paper scorecard.

Usage, from the repo root:

    python3 Benchmarks/arxiv_scorecard/run.py
    python3 Benchmarks/arxiv_scorecard/run.py --sample

The default command scores Benchmarks/arxiv_scorecard/ids.json. --sample
draws a fresh stratified set (seed 20261018) and is what produced that file.
PDFs and HTML are cached under Benchmarks/arxiv_scorecard/cache/ and are not
committed. The scorecard uses the Python port of Cauchy's detector, source
fallback statement index, and section locator; it does not launch the macOS
app or call a model.
"""

from __future__ import annotations

import argparse
import gzip
import io
import json
import random
import re
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / "cache"
IDS_PATH = ROOT / "ids.json"
JSON_OUT = ROOT / "scorecard.json"
MD_OUT = ROOT.parent / "results" / "2026-10-18-arxiv-math-scorecard.md"

CATEGORIES = [
    "math.AG", "math.AT", "math.AP", "math.CO", "math.CT",
    "math.DG", "math.DS", "math.FA", "math.GR", "math.GT",
    "math.LO", "math.CA", "math.NT", "math.NA", "math.OA",
    "math.OC", "math.PR", "math.QA", "math.RT", "math.RA",
]
SEED = 20261018
USER_AGENT = "CauchyScorecard/1.0 (math-paper reference study; mailto:jerryjin@student.unimelb.edu.au)"
ATOM = {"a": "http://www.w3.org/2005/Atom", "arxiv": "http://arxiv.org/schemas/atom"}


def _get(url: str, timeout: int = 90) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                raise
            last_error = error
        except Exception as error:  # noqa: BLE001
            last_error = error
        time.sleep(2 ** attempt)
    raise RuntimeError(f"failed to fetch {url}: {last_error}")


def _arxiv_query(category: str, start: int) -> list[dict]:
    query = urllib.parse.urlencode({
        "search_query": f"cat:{category}",
        "start": start,
        "max_results": 25,
        "sortBy": "submittedDate",
        "sortOrder": "descending",
    })
    payload = _get(f"http://export.arxiv.org/api/query?{query}")
    root = ET.fromstring(payload)
    papers = []
    for entry in root.findall("a:entry", ATOM):
        raw_id = entry.findtext("a:id", default="", namespaces=ATOM)
        arxiv_id = raw_id.rstrip("/").split("/abs/")[-1]
        arxiv_id = re.sub(r"v\d+$", "", arxiv_id)
        papers.append({
            "id": arxiv_id,
            "title": re.sub(r"\s+", " ", entry.findtext("a:title", default="", namespaces=ATOM)).strip(),
            "published": entry.findtext("a:published", default="", namespaces=ATOM)[:10],
            "comment": entry.findtext("arxiv:comment", default="", namespaces=ATOM) or "",
            "categories": [node.attrib.get("term", "") for node in entry.findall("a:category", ATOM)],
            "authors": [
                node.findtext("a:name", default="", namespaces=ATOM)
                for node in entry.findall("a:author", ATOM)
            ],
        })
    return papers


def _accept_html(paper: dict, category: str, used: set[str]) -> dict | None:
    if paper["id"] in used:
        return None
    cached = CACHE / "html" / f"{paper['id']}.html"
    if cached.exists() and cached.stat().st_size > 1000:
        text = cached.read_text(errors="replace")
        if "ltx_ref" in text or "ltx_tag_theorem" in text:
            print(f"  took cached {paper['id']} {paper['title'][:70]}", flush=True)
            return {**paper, "primary_category": category, "role": "random", "html_bytes": cached.stat().st_size}
    try:
        html = _get(f"https://arxiv.org/html/{paper['id']}")
    except Exception as error:  # noqa: BLE001
        print(f"  skip {paper['id']}: {error}", flush=True)
        time.sleep(1)
        return None
    text = html.decode("utf-8", "replace")
    if "ltx_ref" not in text and "ltx_tag_theorem" not in text:
        print(f"  skip {paper['id']}: HTML has no LaTeXML refs", flush=True)
        time.sleep(1)
        return None
    (CACHE / "html").mkdir(parents=True, exist_ok=True)
    (CACHE / "html" / f"{paper['id']}.html").write_text(text)
    print(f"  took {paper['id']} {paper['title'][:70]}", flush=True)
    time.sleep(1)
    return {**paper, "primary_category": category, "role": "random", "html_bytes": len(html)}


def sample_ids(existing: list[dict] | None = None, categories: list[str] | None = None) -> dict:
    rng = random.Random(SEED)
    chosen = list(existing or [])
    used = {paper["id"] for paper in chosen}
    pending = [category for category in (categories or CATEGORIES) if category not in {paper["primary_category"] for paper in chosen}]
    # Replay the offset draws for categories already kept, so a resumed run
    # does not reuse their windows for a later category.
    for category in CATEGORIES:
        start = rng.randrange(0, 50)
        if category not in pending:
            continue
        picked = None
        for window in range(4):
            offset = start + window * 20
            print(f"sampling {category} from offset {offset}", flush=True)
            time.sleep(3)
            try:
                candidates = _arxiv_query(category, offset)
            except Exception as error:  # noqa: BLE001
                print(f"  api failed: {error}", flush=True)
                continue
            rng.shuffle(candidates)
            for paper in candidates:
                picked = _accept_html(paper, category, used)
                if picked is not None:
                    break
            if picked is not None:
                break
        if picked is None:
            raise SystemExit(f"no HTML paper found for {category}")
        used.add(picked["id"])
        chosen.append(picked)
    return {
        "seed": SEED,
        "sampled_on": "2026-10-18",
        "method": (
            "One paper from each of 20 math.* categories. math.MP returns no "
            "hits from the arXiv API, so math.CA stands in for it. For each "
            "category a seed-20261018 offset in 0..49 selects a page of recently "
            "submitted papers; the seeded shuffle's first LaTeXML HTML with "
            "internal refs is kept. If that page has none, later pages are tried."
        ),
        "papers": chosen,
        "edge_cases": [],
    }


def declaration_print_agreement(truth, pages: list[dict]) -> dict:
    """How many HTML declaration numbers actually occur in the PDF text.

    LaTeXML sometimes numbers statements with a global counter (Remark 1,
    equation 2) while the PDF prints the section number (Lemma 5.2, (1.2)).
    A low rate means the score is not a fair reading of Cauchy.
    """
    text = "\n".join(page["text"] for page in pages)
    named_kinds = {
        "theorem", "lemma", "definition", "proposition", "corollary", "remark", "example",
    }
    named = [item for item in truth.declarations if item.kind in named_kinds]
    equations = [item for item in truth.declarations if item.kind == "equation"]

    def named_hit(item) -> bool:
        pattern = re.compile(
            rf"(?i)\b{re.escape(item.kind)}\s+{re.escape(item.number)}(?!\.\d)(?!\d)"
        )
        return pattern.search(text) is not None

    def equation_hit(item) -> bool:
        return re.search(rf"\({re.escape(item.number)}\)", text) is not None

    return {
        "named_in_pdf": sum(named_hit(item) for item in named),
        "named_total": len(named),
        "equations_in_pdf": sum(equation_hit(item) for item in equations),
        "equations_total": len(equations),
    }


def _load_ids() -> dict:
    return json.loads(IDS_PATH.read_text())


def _cache_html(arxiv_id: str) -> str:
    path = CACHE / "html" / f"{arxiv_id}.html"
    if path.exists() and path.stat().st_size > 1000:
        return path.read_text(errors="replace")
    print(f"download html {arxiv_id}", flush=True)
    html = _get(f"https://arxiv.org/html/{arxiv_id}").decode("utf-8", "replace")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(html)
    time.sleep(1)
    return html


def _cache_pdf(arxiv_id: str) -> Path:
    path = CACHE / "pdf" / f"{arxiv_id}.pdf"
    if path.exists() and path.stat().st_size > 1000:
        return path
    print(f"download pdf {arxiv_id}", flush=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_get(f"https://arxiv.org/pdf/{arxiv_id}.pdf"))
    time.sleep(1)
    return path


def _document_class(arxiv_id: str) -> str:
    path = CACHE / "src" / f"{arxiv_id}.bin"
    if not path.exists():
        try:
            print(f"download source {arxiv_id}", flush=True)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(_get(f"https://arxiv.org/e-print/{arxiv_id}", timeout=60))
            time.sleep(1)
        except Exception as error:  # noqa: BLE001
            return f"unavailable ({error.__class__.__name__})"
    blob = path.read_bytes()
    chunks: list[str] = []
    try:
        data = gzip.decompress(blob) if blob[:2] == b"\x1f\x8b" else blob
        if data.startswith(b"\\"):
            chunks.append(data.decode("utf-8", "replace")[:30000])
        else:
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                for member in archive.getmembers():
                    if not member.isfile() or not member.name.endswith((".tex", ".ltx")):
                        continue
                    extracted = archive.extractfile(member)
                    if extracted is None:
                        continue
                    chunks.append(extracted.read(30000).decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        chunks.append(blob.decode("utf-8", "replace")[:20000])
    joined = "\n".join(chunks)
    found = re.search(r"\\documentclass(?:\[[^\]]*\])?\{([^}]+)\}", joined)
    return found.group(1).strip() if found else "not-found"


def _score_paper(record: dict) -> dict:
    sys.path.insert(0, str(ROOT))
    from ground_truth import parse_html, shared_counter
    from pdf_extract import extract_pdf
    from score import attach_structure, make_structure, model_input_estimate, score_profile

    html = _cache_html(record["id"])
    pdf_path = _cache_pdf(record["id"])
    started = time.perf_counter()
    extracted = extract_pdf(str(pdf_path))
    extract_seconds = time.perf_counter() - started
    truth = parse_html(html)
    structure = make_structure(extracted)
    attach_structure(structure)
    profiles = {
        "main": score_profile(truth, extracted["pages"], "main", use_structure=True),
        "hover": score_profile(truth, extracted["pages"], "hover", use_structure=False),
        "chat": score_profile(truth, extracted["pages"], "main", use_structure=True),
        "combined": score_profile(truth, extracted["pages"], "hover", use_structure=True),
    }
    cost = model_input_estimate(extracted["pages"], "main")
    return {
        "id": record["id"],
        "title": record.get("title"),
        "primary_category": record.get("primary_category"),
        "role": record.get("role", "random"),
        "published": record.get("published"),
        "comment": record.get("comment"),
        "page_count": extracted["page_count"],
        "two_column_pages": extracted["two_column_pages"],
        "document_class": record.get("document_class") or _document_class(record["id"]),
        "extract_seconds": round(extract_seconds, 3),
        "declarations": len(truth.declarations),
        "mentions": len(truth.mentions),
        "citation_style": truth.citation_style,
        "citation_count": len(truth.citations),
        "why": record.get("why"),
        "shared_counters": shared_counter(truth.declarations)[:6],
        "print_agreement": declaration_print_agreement(truth, extracted["pages"]),
        "sections": [{"number": section.number, "title": section.title, "level": section.level} for section in truth.sections],
        "model_input": cost,
        "author_year": _author_year_counts(extracted["pages"]),
        "profiles": profiles,
    }


def _author_year_counts(pages: list[dict]) -> dict:
    """Raw PDF text, not the emission counter.

    Parenthetical (Smith 2019) and Smith et al. [2019] are one shape.
    [IK99] and [CF25, Lemma 3.2.2] are the shape this corpus actually prints.
    """
    text = "\n".join(page["text"] for page in pages)
    parenthetical = len(re.findall(
        r"\(([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s+((?:19|20)\d{2})\)",
        text,
    ))
    smith_bracket = len(re.findall(
        r"([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s*\[((?:19|20)\d{2})\]",
        text,
    ))
    keys = re.findall(
        r"\[([A-Z][A-Za-z]*(?:\+[A-Za-z]*)?\d{2,4}[a-z]?)(?:\s*,\s*([^\]\n]{0,80}))?\]",
        text,
    )
    qualified = sum(
        1 for _key, qualifier in keys
        if qualifier and re.search(
            r"(?i)\b(?:theorem|lemma|proposition|corollary|definition|remark|example|equation|eq\.)\b",
            qualifier,
        )
    )
    return {
        "parenthetical": parenthetical,
        "smith_bracket": smith_bracket,
        "author_keys": len(keys),
        "qualified_keys": qualified,
    }


_GATE_ORDER = (
    ("references", "fewer than 8 in-scope references"),
    ("resolution", "resolution under 90%"),
    ("wrong_link", "wrong link"),
    ("citation", "citation emitted as a local reference"),
    ("false_declaration", "indexed statement absent from the HTML"),
    ("section", "section question missed the heading page"),
)


def _gates(card: dict) -> list[str]:
    failed = []
    if card["denominator"] < 8:
        failed.append("references")
    if card["resolution_rate"] < 0.90:
        failed.append("resolution")
    if card["wrong_links"]:
        failed.append("wrong_link")
    if card["citation_detections"]:
        failed.append("citation")
    if card["false_declaration_count"]:
        failed.append("false_declaration")
    if not card["section_questions"]["ok"]:
        failed.append("section")
    return failed


def _first_fail_lines(random_rows: list[dict]) -> list[str]:
    failing = [row for row in random_rows if not row["profiles"]["main"]["passes"]]
    first: dict[str, list[str]] = {key: [] for key, _label in _GATE_ORDER}
    blocked: dict[str, list[str]] = {key: [] for key, _label in _GATE_ORDER}
    for row in failing:
        gates = _gates(row["profiles"]["main"])
        if not gates:
            continue
        first[gates[0]].append(row["id"])
        for gate in gates:
            blocked[gate].append(row["id"])
    lines = [
        "## What the failing papers hit first",
        "",
        f"{len(failing)} of {len(random_rows)} random papers fail on main. "
        "The first check is the earliest gate in the pass rule: enough references, "
        "then 90% resolution, wrong links, citation emissions, false declarations, "
        "and section questions. A later gate can still fail the same paper; "
        "the blocking count is every paper that fails that check.",
        "",
        "| First failing check | Papers | Blocking count |",
        "|---|---:|---:|",
    ]
    for key, label in _GATE_ORDER:
        ids = first[key]
        if not ids and not blocked[key]:
            continue
        lines.append(f"| {label} | {len(ids)} | {len(blocked[key])} |")
    lines.extend(["", "Papers by the first check they fail:", ""])
    for key, label in _GATE_ORDER:
        ids = first[key]
        if not ids:
            continue
        lines.append(f"- **{label}** ({len(ids)}): {', '.join(ids)}")
    lines.append("")
    return lines


def _author_year_lines(random_rows: list[dict]) -> list[str]:
    counted = [row for row in random_rows if row.get("author_year")]
    if not counted:
        return []
    parenthetical = sum(row["author_year"]["parenthetical"] for row in counted)
    smith = sum(row["author_year"]["smith_bracket"] for row in counted)
    keys = sum(row["author_year"]["author_keys"] for row in counted)
    qualified = sum(row["author_year"]["qualified_keys"] for row in counted)
    papers_with_keys = [row["id"] for row in counted if row["author_year"]["author_keys"]]
    main_emitted = sum(row["profiles"]["main"]["citation_detections"] for row in counted)
    hover_emitted = sum(row["profiles"]["hover"]["citation_detections"] for row in counted)
    return [
        "## Author–year citations in the PDF text",
        "",
        f"Across the {len(counted)} random papers, the text layer contains "
        f"{parenthetical} parenthetical citations of the form (Smith 2019) and "
        f"{smith} of the form Smith et al. [2019]. "
        f"It contains {keys} alphanumeric keys such as [IK99], "
        f"{qualified} of them qualified with a theorem, lemma, or equation, "
        f"on {len(papers_with_keys)} papers"
        f"{': ' + ', '.join(papers_with_keys) if papers_with_keys else ''}. "
        f"Main emits {main_emitted} of those spans as local references; "
        f"the hover profile, which still only suppresses numeric brackets, emits {hover_emitted}. "
        "A count of 0 on main is the suppression firing. The HTML citation-style label "
        "does not say author–year, because the HTML cite element often omits the key the PDF prints.",
        "",
    ]


def _fmt_rate(card: dict) -> str:
    return f"{card['resolution_rate']:.0%} ({card['correct']}/{card['denominator']})"


def _search_blurb(rows: list[dict]) -> str:
    comparable = [row for row in rows if not _low_print_agreement(row)]
    exact = sum(1 for row in comparable if row["profiles"]["main"]["number_search"].get("served"))
    have_short = [row for row in comparable if row["profiles"]["main"]["number_search"].get("short_query")]
    short = sum(1 for row in have_short if row["profiles"]["main"]["number_search"].get("short_serves_full_number"))
    literal = sum(1 for row in comparable if row["profiles"]["main"]["number_search"].get("literal_lemma_4_served"))
    return (
        f"An exact printed query such as “Lemma 2.1” is served from the existing index on {exact}/{len(comparable)} "
        f"comparable papers (the key must already be indexed). A shortened query such as “Lemma 2” retrieves the full "
        f"number on {short}/{len(have_short)} of those papers. Literal “Lemma 4” hits a lemma numbered exactly 4 on {literal} papers: "
        "these papers print dotted numbers, so 4.1 is not lemma 4. "
        "A parenthetical name is stored when the PDF prints one; this corpus does not put that name in the HTML theorem tag."
    )


def _agreement_note(row: dict) -> str | None:
    agreement = row.get("print_agreement") or {}
    if not agreement:
        return None
    named = agreement["named_total"]
    equations = agreement["equations_total"]
    note = (
        f"HTML declaration strings found in the PDF: "
        f"{agreement['named_in_pdf']}/{named} named, {agreement['equations_in_pdf']}/{equations} equations."
    )
    if _low_print_agreement(row):
        note += " Named statement numbers in the HTML do not match the PDF, so this resolution rate is not a fair Cauchy score."
    elif equations >= 20 and agreement["equations_in_pdf"] / equations < 0.5:
        note += " Most HTML equation numbers are not printed in the PDF, so equation mentions inflate the miss count."
    return note


def _reference_only(card: dict) -> bool:
    return (
        card["denominator"] >= 8
        and card["resolution_rate"] >= 0.90
        and card["wrong_links"] == 0
        and card["citation_detections"] == 0
        and card["false_declaration_count"] == 0
    )


def _low_print_agreement(row: dict) -> bool:
    """Named HTML numbers that are absent from the PDF. Equation-only drift is noted separately."""
    agreement = row.get("print_agreement") or {}
    named = agreement.get("named_total") or 0
    if named < 8:
        return False
    return agreement["named_in_pdf"] / named < 0.5


def _section_split(rows: list[dict]) -> tuple[int, int, int, int]:
    undotted_ok = undotted_n = dotted_ok = dotted_n = 0
    for row in rows:
        for item in row["profiles"]["combined"]["section_questions"]["probed"]:
            if "." in str(item["number"]):
                dotted_n += 1
                dotted_ok += int(bool(item["ok"]))
            else:
                undotted_n += 1
                undotted_ok += int(bool(item["ok"]))
    return undotted_ok, undotted_n, dotted_ok, dotted_n


def _tickets(rows: list[dict]) -> list[dict]:
    random_rows = [row for row in rows if row["role"] == "random"]
    comparable = [row for row in random_rows if not _low_print_agreement(row)]
    main_citation = sum(row["profiles"]["main"]["citation_detections"] for row in comparable)
    hover_citation = sum(row["profiles"]["hover"]["citation_detections"] for row in comparable)
    worse = [
        row["id"] for row in comparable
        if row["profiles"]["hover"]["citation_detections"] > row["profiles"]["main"]["citation_detections"]
    ]
    edge_worse = [
        f"{row['id']} {row['profiles']['main']['citation_detections']}→{row['profiles']['hover']['citation_detections']}"
        for row in rows if row["role"] != "random"
        and row["profiles"]["hover"]["citation_detections"] > row["profiles"]["main"]["citation_detections"]
    ]
    main_false = sum(row["profiles"]["main"]["false_declaration_count"] for row in comparable)
    undotted_ok, undotted_n, dotted_ok, dotted_n = _section_split(random_rows)
    have_short = [row for row in comparable if row["profiles"]["main"]["number_search"].get("short_query")]
    short_served = sum(
        1 for row in have_short if row["profiles"]["main"]["number_search"].get("short_serves_full_number")
    )
    exact_served = sum(1 for row in comparable if row["profiles"]["main"]["number_search"].get("served"))
    literal = sum(1 for row in comparable if row["profiles"]["main"]["number_search"].get("literal_lemma_4_served"))
    name_served = sum(1 for row in random_rows if row["profiles"]["main"]["number_search"].get("name_query_served_from_index"))
    named = sum(1 for row in random_rows if row["profiles"]["main"]["number_search"].get("printed_name"))
    plural_examples = []
    for row in comparable:
        for item in row["profiles"]["main"]["examples"]["missed"]:
            if re.search(r"Lemmas |Definitions |Theorems |Propositions ", item):
                plural_examples.append(f"{row['id']} {item}")
                break
    tickets = [
        {
            "title": "Match “1. Introduction” when asked what section 1 is about",
            "problem": "AskStructureLocator treats a dotted number such as 9.2 as a section title, and does not treat a top-level heading “N. Title” as section N. Main has no locator, so the question fails there too.",
            "size": "small–medium. The locator already exists on the chat branch; section titles need the undotted leading-number match that chapter titles already use.",
            "evidence": (
                f"On the combined profile, dotted section questions land correctly {dotted_ok}/{dotted_n} times "
                f"and undotted ones {undotted_ok}/{undotted_n} times. "
                f"{sum(1 for row in random_rows if not row['profiles']['combined']['section_questions']['ok'])}/"
                f"{len(random_rows)} papers still miss at least one probed section."
            ),
        },
        {
            "title": "Suppress author–year qualified citations, not only numeric ones",
            "problem": "Hover drops [12, Theorem 3.2], and still emits [IK99, Lemma 1.15] and [CV23, Theorem 3.5] as local references. New abbreviation and plural matches inside those cites can add detections.",
            "size": "small. The qualifier pattern should accept an author key or a year, not only a number before the comma.",
            "evidence": (
                f"Citation-span emissions on the comparable papers go from {main_citation} on main to {hover_citation} on hover. "
                f"Hover is higher on {', '.join(worse) if worse else 'no comparable paper'}"
                f"{'; also ' + ', '.join(edge_worse) + ' outside the 20' if edge_worse else ''}."
            ),
        },
        {
            "title": "Do not index enumerated proof items (1) (2) (3) as equations",
            "problem": "A left-margin line that contains a math arrow passes declarationMatches, so the source-fallback index stores equation keys the paper never displays.",
            "size": "medium. The declaration filter needs a tighter check than “label near the left margin and the line looks like mathematics.”",
            "evidence": (
                f"{main_false} indexed keys on main are absent from the HTML declarations, "
                f"after setting aside papers whose HTML numbers do not match the PDF."
            ),
        },
        {
            "title": "Resolve a shortened number, and plurals on main",
            "problem": "“Lemma 2” now returns Lemma 2.1, and “Lemmas 4.6” is detected. Literal “Lemma 4” still requires a lemma numbered exactly 4.",
            "size": "small.",
            "evidence": (
                f"Exact printed queries are served on {exact_served}/{len(comparable)} comparable papers. "
                f"A shortened first component retrieves the full number on {short_served}/{len(have_short)} papers. "
                f"Literal “Lemma 4” hits a lemma numbered 4 on {literal} papers. "
                f"Plural misses include: {'; '.join(plural_examples[:4]) or 'none recorded'}."
            ),
        },
        {
            "title": "Store the printed statement name on the source-fallback index",
            "problem": "A parenthetical such as “(Zorn)” is now stored on the source-fallback entry. This corpus does not print that name inside the HTML theorem tag, so the measured route stays empty.",
            "size": "small. Parse a parenthetical title into the fallback entry; the term route already exists.",
            "evidence": (
                f"{name_served}/{named} papers expose a parenthetical name in the HTML tag and serve it from the index. "
                "This corpus mostly does not print names inside the theorem tag, so the route is empty rather than wrong."
            ),
        },
    ]
    return tickets


def _write_markdown(payload: dict) -> None:
    rows = [row for row in payload["papers"] if row.get("profiles")]
    random_rows = [row for row in rows if row["role"] == "random"]
    main_pass = sum(1 for row in random_rows if row["profiles"]["main"]["passes"])
    combined_pass = sum(1 for row in random_rows if row["profiles"]["combined"]["passes"])
    lines = [
        "# arXiv maths scorecard",
        "",
        f"**{main_pass} of {len(random_rows)} random papers work with no fixes on main.**",
        f"**{combined_pass} of {len(random_rows)} pass if the open hover and chat branches are both applied.**",
        "",
        "A paper works with no fixes when all of these hold:",
        "",
        "- At least 8 theorem, lemma, definition, equation, or section references are recoverable.",
        "- At least 90% of them resolve. A statement resolves when the detector names the right kind and number and the source-fallback index contains that key. A section reference resolves when “what is section N about” lands on the page that prints the heading.",
        "- There is no wrong link: no citation span opens an indexed statement, no printed reference opens a different statement, and the index contains no statement the HTML does not declare.",
        "- No bracket or author–year citation is emitted as a local reference.",
        "- Every probed “what is section N about” question lands on the heading page.",
        "",
        "Main locates a section written as “N. Title” or “N.N. Title.” "
        "Main also drops a local reference inside [12], [IK99, Lemma 1.15], (Smith 2019), or Smith et al. [2019]; "
        "an interval such as [0, 1] is not a citation. "
        "A bare integer with text to its right, such as “(1) f ∈ W”, is an enumerated item and is not indexed as an equation. A number alone on its line is an equation when the next line is a formula, as in “(1)” followed by “xn+m xn = P(...)”. "
        "“Lemmas 4.6” is lemma 4.6, and “Lemma 2” retrieves a lemma numbered 2.1. "
        "A parenthetical printed on the declaration, such as “(Zorn)”, is stored as the statement name. "
        "Dropping only the section-question condition, "
        f"{sum(_reference_only(row['profiles']['main']) for row in random_rows)} of {len(random_rows)} pass on main and "
        f"{sum(_reference_only(row['profiles']['hover']) for row in random_rows)} of {len(random_rows)} pass on the hover branch. "
        "The headline above keeps the section question.",
        "",
        "A bracket that the detector does not open is not a wrong link. "
        "The heading page for a section question is the PDF outline entry whose title matches the HTML heading, "
        "or else a title-shaped line. A numbered sentence is not that heading. "
        "An outline bookmark that reads “Introduction” rather than “1. Introduction” is still section 1 when it is the first section bookmark. "
        "A citation bracket may be split by a line break, as in “[17, Theorem 3.31(c)]”. "
        "The HTML declaration list includes a plural tag such as “Examples 6.7” and a bold run-in such as “Remark 3.13.”",
        "",
        (
            f"Shared counters, such as a theorem followed by a lemma with the next number, "
            f"appear on {sum(1 for row in random_rows if row['shared_counters'])} of {len(random_rows)} papers. "
            "The index key is the kind plus the full number, so the pair resolves when both declarations are indexed."
        ),
        "",
        "Text comes from PyMuPDF’s content stream, the stand-in for `PDFPage.string`. Equation x-positions are glyph-box fractions, the stand-in for PDFKit selection bounds. No model is called; index time is the deterministic source fallback. Token estimates are input size only and were not billed.",
        "",
        _search_blurb(random_rows),
        "",
        *_first_fail_lines(random_rows),
        *_author_year_lines(random_rows),
        "## Random papers",
        "",
        "| arXiv | cat | pages | class | main | hover | chat | both | index s | model toks |",
        "|---|---|---:|---|---|---|---|---|---:|---:|",
    ]
    for row in random_rows:
        profiles = row["profiles"]
        lines.append(
            "| {id} | {cat} | {pages} | {klass} | {main} | {hover} | {chat} | {both} | {seconds:.1f} | {tokens} |".format(
                id=row["id"],
                cat=row["primary_category"].replace("math.", ""),
                pages=row["page_count"],
                klass=row["document_class"],
                main="pass" if profiles["main"]["passes"] else _fmt_rate(profiles["main"]),
                hover="pass" if profiles["hover"]["passes"] else _fmt_rate(profiles["hover"]),
                chat="pass" if profiles["chat"]["passes"] else _fmt_rate(profiles["chat"]),
                both="pass" if profiles["combined"]["passes"] else _fmt_rate(profiles["combined"]),
                seconds=profiles["main"]["index_seconds"] + row["extract_seconds"],
                tokens=row["model_input"]["estimated_input_tokens"],
            )
        )
    edges = [row for row in rows if row["role"] != "random"]
    if edges:
        longest = max((row["page_count"] for row in random_rows), default=0)
        two_col = sum(row["two_column_pages"] for row in random_rows)
        lines.extend([
            "",
            "## Edge cases kept outside the 20",
            "",
            f"The random sample’s longest paper is {longest} pages and it has {two_col} two-column pages. "
            "The papers below are scored the same way and are not part of the headline.",
            "",
        ])
        for row in edges:
            main = row["profiles"]["main"]
            lines.append(
                f"- {row['id']} ({row['role']}, {row['page_count']} pages, "
                f"{row['two_column_pages']} two-column, `{row['document_class']}`): "
                f"main {_fmt_rate(main)}, pass={main['passes']}. {row.get('why') or ''}"
            )
    lines.extend(["", "## Per paper", ""])
    for row in rows:
        main = row["profiles"]["main"]
        combined = row["profiles"]["combined"]
        lines.append(f"### {row['id']} — {row['title']}")
        lines.append("")
        lines.append(
            f"{row['primary_category']}, {row['page_count']} pages, "
            f"{row['two_column_pages']} two-column pages, class `{row['document_class']}`, "
            f"citations {row['citation_style']} ({row['citation_count']}). "
            f"Role: {row['role']}."
        )
        if row.get("why"):
            lines.append(row["why"])
        if row["shared_counters"]:
            lines.append("Shared counters: " + "; ".join(row["shared_counters"]) + ".")
        agreement = _agreement_note(row)
        if agreement:
            lines.append(agreement)
        lines.append(
            f"Main resolves {_fmt_rate(main)}; misses {main['missed']}, "
            f"extraction gaps {main['extraction_misses']}, wrong links {main['wrong_links']}, "
            f"citation emissions {main['citation_detections']} "
            f"({main['citation_links']} of them indexed), "
            f"false declarations {main['false_declaration_count']}. "
            f"Index built in {main['index_seconds']:.2f}s plus {row['extract_seconds']:.2f}s extraction. "
            f"A model pass would send about {row['model_input']['estimated_input_tokens']} input tokens "
            f"across {row['model_input']['pages_that_would_call_the_model']} pages."
        )
        lines.append("Main fails: " + "; ".join(main["fail_reasons"]) + ".")
        if combined["fail_reasons"]:
            lines.append("Hover+chat fails: " + "; ".join(combined["fail_reasons"]) + ".")
        search = main["number_search"]
        lines.append(
            f"Number search `{search.get('query')}` served: {search.get('served')}. "
            f"Short query `{search.get('short_query')}` serves the full number: {search.get('short_serves_full_number')}. "
            f"`Lemma 4` hits lemma 4: {search.get('literal_lemma_4_served')}. "
            f"Printed name served: {search.get('name_query_served_from_index')} ({search.get('printed_name')})."
        )
        for label, bucket in (("Missed", main["examples"]["missed"]), ("Wrong", main["examples"]["wrong"]), ("Citation", main["examples"]["citation"])):
            if bucket:
                lines.append(f"{label}:")
                for item in bucket:
                    lines.append(f"- {item}")
        questions = combined["section_questions"]["probed"]
        if questions:
            lines.append("Section questions (hover+chat):")
            for item in questions:
                mark = "ok" if item["ok"] else "miss"
                lines.append(
                    f"- {mark} `{item['question']}` → p.{None if item['predicted_page'] is None else item['predicted_page'] + 1} "
                    f"(heading on p.{None if item['truth_page'] is None else item['truth_page'] + 1}, {item['title'][:60]})"
                )
        lines.append("")
    lines.extend(["## Proposed tickets", ""])
    for index, ticket in enumerate(_tickets(rows), start=1):
        lines.append(f"{index}. **{ticket['title']}** — {ticket['problem']} Size: {ticket['size']} Evidence: {ticket['evidence']}")
    lines.append("")
    MD_OUT.parent.mkdir(parents=True, exist_ok=True)
    MD_OUT.write_text("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", action="store_true", help="draw a new id list and replace ids.json")
    parser.add_argument("--limit", type=int, default=0, help="score only the first N random papers")
    args = parser.parse_args()
    if args.sample or not IDS_PATH.exists():
        payload = sample_ids()
        if IDS_PATH.exists():
            payload["edge_cases"] = _load_ids().get("edge_cases") or []
        IDS_PATH.write_text(json.dumps(payload, indent=2) + "\n")
    else:
        payload = _load_ids()
    records = list(payload["papers"])
    if args.limit:
        records = records[: args.limit]
    records.extend(payload.get("edge_cases") or [])
    rows = []
    for record in records:
        print(f"scoring {record['id']}", flush=True)
        try:
            rows.append(_score_paper(record))
        except Exception as error:  # noqa: BLE001
            print(f"FAILED {record['id']}: {error}", flush=True)
            rows.append({
                "id": record["id"],
                "title": record.get("title"),
                "primary_category": record.get("primary_category"),
                "role": record.get("role", "random"),
                "error": str(error),
                "profiles": {},
            })
        JSON_OUT.write_text(json.dumps({"papers": rows}, indent=2) + "\n")
        _write_markdown({"papers": rows})
        profile = rows[-1].get("profiles", {}).get("main")
        if profile is None:
            print(f"  no score ({rows[-1].get('error', 'unknown')})", flush=True)
        else:
            print(
                f"  main {profile['resolution_rate']:.0%} "
                f"pass={profile['passes']} "
                f"combined pass={rows[-1]['profiles']['combined']['passes']}",
                flush=True,
            )
    random_rows = [row for row in rows if row["role"] == "random" and row.get("profiles")]
    print(
        f"HEADLINE main {sum(row['profiles']['main']['passes'] for row in random_rows)}/{len(random_rows)} "
        f"combined {sum(row['profiles']['combined']['passes'] for row in random_rows)}/{len(random_rows)}",
        flush=True,
    )


if __name__ == "__main__":
    main()
