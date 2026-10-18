"""Score one paper against main, the hover branch, and the chat branch.

"Works with no fixes" means all of the following, on that code path:

- At least 8 in-scope references are recoverable (theorem, lemma, definition,
  equation, section). Fewer than that is not a pass.
- At least 90% of those references resolve. A statement reference resolves
  when the detector covers the printed span with the right kind and number
  and the source-fallback statement index contains that key. A section
  reference resolves when "what is section N about" locates the body page
  that prints the section heading. Main has no section locator, so those
  references stay unresolved there.
- No wrong link. A wrong link is a hover that would open: a citation span
  whose detector hit is in the index, a printed reference resolved to a
  different indexed statement, or an index entry that is not a real
  declaration in the HTML.
- No bracket or author-year citation is emitted as a local reference, even
  when that reference is not in the index.
- Every probed "what is section N about" question lands on the heading's page.
"""

from __future__ import annotations

import re
import time
from collections import defaultdict

from cauchy_logic import (
    PageSnapshot,
    StatementIndex,
    Structure,
    all_references,
    build_statement_index,
    is_likely_table_of_contents,
    locate,
    structural_query,
)
from ground_truth import IN_SCOPE, PaperTruth
from pdf_extract import equation_label_x

PASS_MIN_RESOLUTION = 0.90
PASS_MIN_REFERENCES = 8

_KIND_PATTERN = {
    "theorem": r"theorems?|thm\.?",
    "lemma": r"lemmas?|lem\.?",
    "definition": r"definitions?|def\.?",
    "proposition": r"propositions?|prop\.?",
    "corollary": r"corollar(?:y|ies)|cor\.?",
    "remark": r"remarks?",
    "example": r"examples?",
    "exercise": r"exercises?",
    "proof": r"proofs?",
}

_CITE = re.compile(
    r"\[[^\[\]\n]{0,120}\]"
)
_YEAR = re.compile(r"(?<!\d)(?:19|20)\d{2}(?!\d)")


def _boundary_number(number: str) -> str:
    # A heading is often "Theorem 2.1." The period is punctuation, not part of
    # a longer number. Reject only a following digit or a dotted continuation.
    return re.escape(number) + r"(?!\.\d)(?!\d)"


def _patterns(kind: str, number: str) -> list[re.Pattern[str]]:
    token = _boundary_number(number)
    if kind == "section":
        return [
            re.compile(rf"(?i)\b(?:sections?|sec\.?)\s*{token}"),
            re.compile(rf"(?i)§\s*{token}"),
            re.compile(rf"(?i)\bappendices\s+{token}|\bappendix\s*{token}\b"),
        ]
    if kind == "equation":
        return [re.compile(rf"(?i)(?:\beq(?:uation)?\.?\s*)?\(\s*{re.escape(number)}\s*\)")]
    word = _KIND_PATTERN.get(kind)
    if word is None:
        return []
    return [
        re.compile(rf"(?i)\b(?:{word})\s*{token}"),
        re.compile(rf"(?i)\b(?:{word})\s*\(\s*{re.escape(number)}\s*\)"),
    ]


def _citation_spans(text: str) -> list[tuple[int, int]]:
    spans = []
    for found in _CITE.finditer(text):
        body = found.group(0)
        if (
            re.search(r"\d", body)
            or re.search(r"(?i)\b(?:theorem|lemma|proposition|corollary|definition|thm|lem|prop)\b", body)
            or _YEAR.search(body)
            or re.search(r"\[[A-Z][A-Za-z.\-]+", body)
        ):
            spans.append((found.start(), found.end()))
    return spans


def _inside(spans: list[tuple[int, int]], start: int, end: int) -> bool:
    return any(span_start <= start and end <= span_end for span_start, span_end in spans)


def _true_section_page(pages: list[dict], number: str, title: str) -> int | None:
    words = re.findall(r"[A-Za-z]{4,}", title)[:3]
    number_pattern = re.compile(
        rf"(?i)^\s*(?:§\s*|section\s+|appendix\s+)?{re.escape(number)}(?:\.(?!\d))?(?!\d)"
    )
    for page in pages:
        if is_likely_table_of_contents(page["text"]):
            continue
        for raw in page["text"].split("\n"):
            line = raw.strip()
            if not number_pattern.search(line):
                continue
            lowered = line.lower()
            if words and not all(word.lower() in lowered for word in words[:2]):
                continue
            if len(line) > 160:
                continue
            return page["page_index"]
    return None


def _section_questions(truth: PaperTruth, pages: list[dict], structure: Structure | None) -> dict:
    candidates = [section for section in truth.sections if re.fullmatch(r"\d+(?:\.\d+)?", section.number)]
    level1 = [section for section in candidates if section.level == 1] or candidates
    if not level1:
        return {"probed": [], "ok": False, "reason": "no numbered section heading in the HTML"}
    picks = [level1[0], level1[len(level1) // 2], level1[-1]]
    subsections = [section for section in candidates if section.level == 2]
    if subsections:
        picks.append(subsections[len(subsections) // 2])
    seen: set[str] = set()
    probed = []
    for section in picks:
        if section.number in seen:
            continue
        seen.add(section.number)
        truth_page = _true_section_page(pages, section.number, section.title)
        question = f"what is section {section.number} about"
        query = structural_query(question)
        found = None if structure is None or query is None else locate(query, structure)
        predicted = None if found is None else found.start_page
        probed.append({
            "question": question,
            "number": section.number,
            "title": section.title,
            "truth_page": truth_page,
            "predicted_page": predicted,
            "label": None if found is None else found.label,
            "ok": truth_page is not None and predicted == truth_page,
        })
    return {
        "probed": probed,
        "ok": bool(probed) and all(item["ok"] for item in probed),
        "reason": None if probed and all(item["ok"] for item in probed) else "a section question missed its heading page",
    }


def _hits_for(pages: list[dict], kind: str, number: str) -> list[tuple[int, int, int, str]]:
    found = []
    patterns = _patterns(kind, number)
    for page in pages:
        occupied: list[tuple[int, int]] = []
        for pattern in patterns:
            for match in pattern.finditer(page["text"]):
                if any(not (match.end() <= start or match.start() >= end) for start, end in occupied):
                    continue
                occupied.append((match.start(), match.end()))
                found.append((page["page_index"], match.start(), match.end(), match.group(0)))
    return found


def _page_maps(pages: list[dict], profile: str) -> tuple[dict[int, list], dict[int, list[tuple[int, int]]]]:
    matches = {}
    cites = {}
    prepared = []
    for page in pages:
        text = page["text"]
        prepared.append({
            **page,
            "equation_label_x": equation_label_x(page, profile),
        })
        matches[page["page_index"]] = all_references(text, profile)
        cites[page["page_index"]] = _citation_spans(text)
    return matches, cites, prepared


def score_profile(
    truth: PaperTruth,
    pages: list[dict],
    profile: str,
    use_structure: bool,
) -> dict:
    started = time.perf_counter()
    matches, cites, prepared = _page_maps(pages, profile)
    index = build_statement_index(prepared, profile)
    index_seconds = time.perf_counter() - started

    structure = score_profile.structure if use_structure else None

    grouped: dict[tuple[str, str], int] = defaultdict(int)
    for mention in truth.mentions:
        if mention.in_citation or mention.kind not in IN_SCOPE:
            continue
        grouped[(mention.kind, mention.number)] += 1

    correct = 0
    missed = 0
    wrong = 0
    extraction_misses = 0
    examples: dict[str, list] = {"missed": [], "wrong": [], "citation": []}
    questions = _section_questions(truth, pages, structure)
    section_cache = {item["number"]: item["ok"] for item in questions["probed"]}
    for number in {item[1] for item in grouped if item[0] == "section"}:
        if number in section_cache:
            continue
        title = next((section.title for section in truth.sections if section.number == number), "")
        truth_page = _true_section_page(pages, number, title)
        query = None if structure is None else structural_query(f"what is section {number} about")
        found = None if query is None else locate(query, structure)
        section_cache[number] = truth_page is not None and found is not None and found.start_page == truth_page

    for (kind, number), html_count in sorted(grouped.items()):
        hits = _hits_for(pages, kind, number)
        extraction_misses += max(0, html_count - len(hits))
        for page_index, start, end, surface in hits:
            if _inside(cites.get(page_index, []), start, end):
                wrong += 1
                _add(examples["wrong"], f"p.{page_index + 1} {surface!r} sits inside a citation")
                continue
            if kind == "section":
                if section_cache.get(number) is True:
                    correct += 1
                else:
                    missed += 1
                    _add(examples["missed"], f"p.{page_index + 1} {surface!r} did not locate section {number}")
                continue
            covering = [
                match for match in matches.get(page_index, [])
                if match.start < end and match.end > start
            ]
            good = [match for match in covering if match.kind == kind and match.number == number]
            if good and index.lookup(kind, number) is not None:
                correct += 1
                continue
            bad = next((match for match in covering if index.lookup(match.kind, match.number)), None)
            if bad is not None and (bad.kind, bad.number) != (kind, number):
                wrong += 1
                _add(examples["wrong"], f"p.{page_index + 1} {surface!r} opened {bad.kind} {bad.number}")
                continue
            missed += 1
            if not covering:
                reason = "detector missed it"
            elif index.lookup(kind, number) is None:
                reason = "not in the statement index"
            else:
                reason = "detector labelled it differently and the label is not indexed"
            _add(examples["missed"], f"p.{page_index + 1} {surface!r}: {reason}")

    citation_detections = 0
    citation_links = 0
    for page in pages:
        for match in matches.get(page["page_index"], []):
            if not _inside(cites.get(page["page_index"], []), match.start, match.end):
                continue
            citation_detections += 1
            snippet = page["text"][max(0, match.start - 24) : match.end + 24].replace("\n", " ")
            _add(examples["citation"], f"p.{page['page_index'] + 1} {match.kind} {match.number} in {snippet!r}")
            if index.lookup(match.kind, match.number) is not None:
                citation_links += 1

    false_keys = []
    for key, entry in index.entries.items():
        if key in truth.declaration_keys:
            continue
        if entry.kind not in IN_SCOPE and entry.kind not in {"proposition", "corollary", "remark", "example"}:
            continue
        false_keys.append(f"p.{entry.page_index + 1} {entry.kind} {entry.number}")
    false_keys.sort()

    denominator = correct + missed + wrong + extraction_misses
    rate = 1.0 if denominator == 0 else correct / denominator
    questions_ok = questions["ok"] if use_structure else False
    passes = (
        denominator >= PASS_MIN_REFERENCES
        and rate >= PASS_MIN_RESOLUTION
        and wrong == 0
        and citation_detections == 0
        and not false_keys
        and questions_ok
    )
    return {
        "profile": profile,
        "structure": use_structure,
        "passes": passes,
        "resolution_rate": round(rate, 4),
        "correct": correct,
        "missed": missed,
        "wrong_links": wrong,
        "extraction_misses": extraction_misses,
        "denominator": denominator,
        "citation_detections": citation_detections,
        "citation_links": citation_links,
        "false_declarations": false_keys[:12],
        "false_declaration_count": len(false_keys),
        "index_size": len(index),
        "index_seconds": round(index_seconds, 3),
        "section_questions": questions,
        "examples": examples,
        "number_search": number_search(index, truth, profile),
        "fail_reasons": _fail_reasons(denominator, rate, wrong, citation_detections, false_keys, questions_ok, use_structure),
    }


def _fail_reasons(denominator, rate, wrong, citations, false_keys, questions_ok, use_structure) -> list[str]:
    reasons = []
    if denominator < PASS_MIN_REFERENCES:
        reasons.append(f"only {denominator} in-scope refs (need {PASS_MIN_REFERENCES})")
    if rate < PASS_MIN_RESOLUTION:
        reasons.append(f"resolution {rate:.1%} is under 90%")
    if wrong:
        reasons.append(f"{wrong} wrong link" if wrong == 1 else f"{wrong} wrong links")
    if citations:
        if citations == 1:
            reasons.append("1 citation span emitted as a local ref")
        else:
            reasons.append(f"{citations} citation spans emitted as local refs")
    if false_keys:
        count = len(false_keys)
        noun = "statement" if count == 1 else "statements"
        verb = "is" if count == 1 else "are"
        reasons.append(f"{count} indexed {noun} {verb} not in the HTML declarations")
    if not questions_ok:
        reasons.append(
            "section questions are not implemented"
            if not use_structure
            else "a section question missed its heading page"
        )
    return reasons


def _add(bucket: list, item: str, limit: int = 6) -> None:
    if len(bucket) < limit and item not in bucket:
        bucket.append(item)


def number_search(index: StatementIndex, truth: PaperTruth, profile: str) -> dict:
    lemmas = [item for item in truth.declarations if item.kind == "lemma"]
    theorems = [item for item in truth.declarations if item.kind == "theorem"]
    named = next((item for item in truth.declarations if item.name), None)
    chosen = lemmas[0] if lemmas else (theorems[0] if theorems else None)
    if chosen is None:
        literal = index.statements_cited_in("Lemma 4", profile)
        return {
            "query": "Lemma 4",
            "served": False,
            "reason": "this paper has no lemma or theorem to look up",
            "literal_lemma_4": [f"{item.kind} {item.number}" for item in literal],
        }
    exact = index.statements_cited_in(f"{chosen.kind.title()} {chosen.number}", profile)
    head = chosen.number.split(".")[0]
    shortened = index.statements_cited_in(f"{chosen.kind.title()} {head}", profile)
    literal = index.statements_cited_in("Lemma 4", profile)
    name_query = None
    name_served = False
    if named and named.name:
        name_query = f"the {named.kind} of {named.name}"
        # Source-fallback entries do not store printed names, so the term route
        # has nothing to match. Record that explicitly.
        name_served = any(entry.name and named.name.lower() in entry.name.lower() for entry in index.entries.values())
    return {
        "query": f"{chosen.kind.title()} {chosen.number}",
        "served": any(item.kind == chosen.kind and item.number == chosen.number for item in exact),
        "short_query": None if head == chosen.number else f"{chosen.kind.title()} {head}",
        "short_serves_full_number": any(item.number == chosen.number for item in shortened),
        "literal_lemma_4_served": any(item.kind == "lemma" and item.number == "4" for item in literal),
        "printed_name": None if named is None else {"kind": named.kind, "number": named.number, "name": named.name},
        "name_query_served_from_index": name_served,
        "name_query": name_query,
    }


def model_input_estimate(pages: list[dict], profile: str) -> dict:
    """Characters the model indexer would send. No model is called.

    processPage skips a page unless declarationMatches is non-empty, then
    sends the instructions plus at most 12_000 characters of page text.
    """
    instruction_chars = 3_400
    pages_sent = 0
    characters = 0
    for page in pages:
        text = page["text"]
        if not text.strip() or is_likely_table_of_contents(text):
            continue
        if not all_references(text, profile):
            continue
        from cauchy_logic import declaration_matches

        if not declaration_matches(text, equation_label_x(page, profile), profile):
            continue
        pages_sent += 1
        characters += instruction_chars + min(len(text), 12_000)
    return {
        "pages_that_would_call_the_model": pages_sent,
        "estimated_input_characters": characters,
        "estimated_input_tokens": characters // 4,
        "billed": False,
    }


def attach_structure(structure: Structure | None) -> None:
    score_profile.structure = structure


attach_structure(None)


def make_structure(extracted: dict) -> Structure:
    return Structure(
        outline=extracted["outline"],
        pages=[PageSnapshot(page["page_index"], page["text"]) for page in extracted["pages"] if page["text"].strip()],
        page_count=extracted["page_count"],
    )
