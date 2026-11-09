"""Score one paper against main, the hover branch, and the chat branch.

"Works with no fixes" means all of the following, on that code path:

- At least 8 in-scope references are recoverable (theorem, lemma, definition,
  equation, section). Fewer than that is not a pass.
- At least 90% of those references resolve. A statement reference resolves
  when the detector covers the printed span with the right kind and number
  and the source-fallback statement index contains that key. A section
  reference resolves when "what is section N about" locates the body page
  that prints the section heading. Main locates a heading written as
  “N. Title” or “N.N. Title.”
- No wrong link. A wrong link is a hover that would open a citation span
  whose detector hit is in the index, or a printed reference resolved to a
  different indexed statement.
- No indexed statement that the HTML does not declare, unless the PDF text
  prints that statement as a heading. A heading starts a line: "Proposition
  3.2.", "Proposition 3.2 (Name)", "Proposition 3.2:", or "3.2. Proposition."
  "by Proposition 3.2" and "see Remark 3.12." are mentions. An equation tag
  or a section title is not this exception.
- No bracket or author-year citation is emitted as a local reference, even
  when that reference is not in the index.
- Every probed "what is section N about" question lands on the heading's page.
"""

from __future__ import annotations

import re
import time
from collections import defaultdict

from cauchy_logic import (
    OutlineNode,
    PageSnapshot,
    StatementIndex,
    Structure,
    _external_citation_spans,
    _number_sort_key,
    all_references,
    build_statement_index,
    _explicit_section_number,
    _is_line_start_statement,
    fold_ligatures,
    heading_line,
    logical_lines,
    is_likely_table_of_contents,
    locate,
    part_letter_bases,
    structural_query,
)
from ground_truth import IN_SCOPE, PaperTruth
from pdf_extract import equation_label_x

PASS_MIN_RESOLUTION = 0.90
PASS_MIN_REFERENCES = 8
# Same number token the detector uses inside a plural list.
_REFERENCE_NUMBER = r"(?:\d+(?:\.\d+)*|[A-Z](?:\.\d+)+)"

_KIND_PATTERN = {
    "theorem": r"theorems?|thm\.?",
    "lemma": r"lemmas?|lem\.?",
    # "Deﬁnition" uses the ﬁ ligature. Same fold as the app keyword pattern.
    "definition": fold_ligatures(r"definitions?|def\.?"),
    "proposition": r"propositions?|prop\.?",
    "corollary": r"corollar(?:y|ies)|cor\.?",
    "remark": r"remarks?",
    "example": r"examples?",
    "exercise": r"exercises?",
    "proof": r"proofs?",
}

# Numbered statements whose printed heading is "Proposition 3.2". Equation
# tags and section titles stay on the HTML declaration list: "(3.2)" and
# "1. Introduction" are not this heading.
_PDF_HEADING_KINDS = {
    "theorem", "lemma", "proposition", "corollary", "definition", "remark", "example",
}



def _boundary_number(number: str) -> str:
    # A heading is often "Theorem 2.1." The period is punctuation, not part of
    # a longer number. Reject only a following digit or a dotted continuation.
    return re.escape(number) + r"(?!\.\d)(?!\d)"


def _at_line_start(text: str, index: int) -> bool:
    line_start = text.rfind("\n", 0, index) + 1
    return text[line_start:index].strip() == ""


def _line_around(text: str, start: int, end: int) -> str:
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    if line_end < 0:
        line_end = len(text)
    line = " ".join(text[line_start:line_end].split())
    if len(line) > 300:
        return line[:300].rstrip() + "…"
    return line


def _pdf_statement_hits(pages: list[dict], kind: str, number: str) -> tuple[dict | None, dict | None]:
    """The first heading line, and the first in-text line, for this statement.

    A heading starts a line and reads as a statement, not a mention. The kind
    word comes first ("Proposition 3.2.", "Proposition 3.2 (Name)",
    "Lemma 9:") or the number does ("3.2. Proposition."). The same test the
    reader uses for a line-start statement rejects a comma ("Proposition 3.6,
    we have") and a dot leader ("Proposition 3.2 .... 12"). "by Proposition
    3.2" and "see Remark 3.12." do not start the line. "Proposition 3.20" is
    a different number. The ﬁ ligature in "Deﬁnition" is the PDF's "fi".

    The in-text line is kept so a rejection can be spot-checked.
    """
    if kind not in _PDF_HEADING_KINDS or not number:
        return None, None
    word = fold_ligatures(kind)
    token = _boundary_number(number)
    kind_first = re.compile(rf"(?i)\b(?:{word})[ \t]+{token}")
    number_first = re.compile(rf"(?im)^[ \t]*{token}\.?[ \t]+(?:{word})\b")
    heading: dict | None = None
    mention: dict | None = None
    for page in pages:
        text = page.get("text") or ""
        if not text:
            continue
        hits: list[tuple[int, int, str, bool]] = []
        for match in kind_first.finditer(text):
            is_heading = _at_line_start(text, match.start()) and _is_line_start_statement(text[match.end():])
            hits.append((match.start(), match.end(), "line-start", is_heading))
        for match in number_first.finditer(text):
            is_heading = _is_line_start_statement(text[match.end():])
            hits.append((match.start(), match.end(), "number-first", is_heading))
        for start, end, form, is_heading in sorted(hits):
            found = {
                "page_index": page["page_index"],
                "line": _line_around(text, start, end),
                "form": form if is_heading else "mention",
            }
            if is_heading:
                if heading is None:
                    heading = found
            elif mention is None:
                mention = found
        if heading is not None and mention is not None:
            return heading, mention
    return heading, mention


def pdf_statement_heading(pages: list[dict], kind: str, number: str) -> dict | None:
    """The PDF line that prints this statement as a heading, if there is one."""
    heading, _mention = _pdf_statement_hits(pages, kind, number)
    return heading


def pdf_statement_mention(pages: list[dict], kind: str, number: str) -> dict | None:
    """A non-heading line that still contains the kind word and exact number."""
    _heading, mention = _pdf_statement_hits(pages, kind, number)
    return mention


def _patterns(kind: str, number: str) -> list[re.Pattern[str]]:
    token = _boundary_number(number)
    if kind == "section":
        # "Subsection 2.3" and "Subsubsection 6.2.1" name that numbered unit.
        return [
            re.compile(rf"(?i)\b(?:sub(?:sub)?sections?|sections?|sec\.?)\s*{token}"),
            re.compile(rf"(?i)§\s*{token}"),
            re.compile(rf"(?i)\bappendices\s+{token}|\bappendix\s*{token}\b"),
        ]
    if kind == "equation":
        # "(2.7a)" prints equation 2.7. A bare "(7a)" prints equation 7 only
        # when the page also prints another part letter; _hits_for adds that
        # pattern. A lone "(1a)" does not.
        letter = r"[a-z]" if "." in number else ""
        optional = f"{letter}?" if letter else ""
        return [re.compile(rf"(?i)(?:\beq(?:uation)?\.?\s*)?\(\s*{re.escape(number)}{optional}\s*\)")]
    word = _KIND_PATTERN.get(kind)
    if word is None:
        return []
    # "Lemmas 3.1, 3.2 and 3.4" names 3.2 and 3.4. The kind word sits on the
    # first number only. The captured group is that later number, so a hit
    # does not cover the earlier numbers in the same list.
    later = (
        rf"(?i)\b(?:{word})\s*{_REFERENCE_NUMBER}"
        rf"(?:\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?{_REFERENCE_NUMBER})*"
        rf"\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?({token})"
    )
    return [
        re.compile(rf"(?i)\b(?:{word})\s*{token}"),
        re.compile(rf"(?i)\b(?:{word})\s*\(\s*{re.escape(number)}\s*\)"),
        re.compile(later),
    ]


def _citation_spans(text: str) -> list[tuple[int, int]]:
    # The same brackets the detector refuses to open, including one that the
    # text layer splits across a line: "[Zho23,\nTheorem 1.1]".
    return _external_citation_spans(text)


def _inside(spans: list[tuple[int, int]], start: int, end: int) -> bool:
    return any(span_start <= start and end <= span_end for span_start, span_end in spans)


def _norm_title(title: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()
    # "3.3. Steinberg splitting" and "Steinberg splitting" name the same heading.
    cleaned = re.sub(r"^(?:(?:section|sec)\s+)?(?:\d+\s+)+", "", cleaned)
    # Rendered math puts a space inside a symbol: "SL 2" and "SL2".
    cleaned = re.sub(r"(?<=[a-z])\s+(?=\d)", "", cleaned)
    cleaned = re.sub(r"(?<=\d)\s+(?=[a-z])", "", cleaned)
    return cleaned.strip()


def _titles_agree(wanted: str, got: str) -> bool:
    if not wanted or not got:
        return False
    if wanted == got:
        return True
    # A shortened bookmark still names the same heading. Short titles such
    # as "Introduction" only match exactly, so a later "Introduction to X"
    # does not steal them.
    if len(wanted) < 18 or len(got) < 18:
        return False
    return got.startswith(wanted + " ") or wanted.startswith(got + " ")


def _outline_title_page(outline: list[OutlineNode], title: str, number: str | None = None) -> int | None:
    wanted = _norm_title(title)
    found: list[tuple[int, int, int]] = []

    def walk(nodes: list[OutlineNode], depth: int = 0) -> None:
        for node in nodes:
            got = _norm_title(node.title)
            # "2. Shared title" is not the heading for section 2.2, even when
            # the subsection repeats the parent's title.
            bookmark_number = _explicit_section_number(node.title)
            number_ok = not number or not bookmark_number or bookmark_number == number
            if node.page_index >= 0 and number_ok and _titles_agree(wanted, got):
                found.append((abs(len(got) - len(wanted)), depth, node.page_index))
            walk(node.children, depth + 1)

    walk(outline)
    if not found:
        return None
    found.sort()
    return found[0][2]


def _true_section_page(
    pages: list[dict],
    number: str,
    title: str,
    outline: list[OutlineNode] | None = None,
) -> int | None:
    # The bookmark title is the author's own heading. A numbered sentence
    # on an earlier page ("3. Numerical experiments ... GPU-Preprocessor")
    # is not that heading.
    if outline:
        bookmarked = _outline_title_page(outline, title, number)
        if bookmarked is not None:
            return bookmarked
    words = re.findall(r"[A-Za-z]{4,}", title)[:3]
    # "2.4. Small cases" is section 2.4, not section 2.
    number_pattern = re.compile(
        rf"(?i)^\s*(?:§\s*|section\s+|appendix\s+)?{re.escape(number)}(?!\.\d)(?!\d)"
    )
    for page in pages:
        if is_likely_table_of_contents(page["text"]):
            continue
        for raw in logical_lines(page["text"], page.get("line_bold"), page.get("line_italic")):
            line = raw.strip()
            heading = heading_line(line)
            if heading is None:
                continue
            if not number_pattern.search(heading):
                continue
            lowered = heading.lower()
            if words and not all(word.lower() in lowered for word in words[:2]):
                continue
            if len(heading) > 160:
                continue
            return page["page_index"]
    # The HTML title can split math ("S 1 2 ( r )") so it matches neither the
    # bookmark nor a heading line. The locator still answers from the section
    # number printed on the bookmark. A title match and a heading line above
    # keep priority over that number.
    if outline:
        numbered = _outline_section_page(outline, number)
        if numbered is not None:
            return numbered
    return None


def _outline_section_page(outline: list[OutlineNode], number: str) -> int | None:
    """Page of the bookmark whose printed section number is `number`.

    The shallowest bookmark wins, so a section is preferred to a later
    repeat of the same number.
    """
    found: list[tuple[int, int]] = []

    def walk(nodes: list[OutlineNode], depth: int = 0) -> None:
        for node in nodes:
            bookmark_number = _explicit_section_number(node.title)
            if node.page_index >= 0 and bookmark_number == number:
                found.append((depth, node.page_index))
            walk(node.children, depth + 1)

    walk(outline)
    if not found:
        return None
    found.sort()
    return found[0][1]


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
        outline = None if structure is None else structure.outline
        truth_page = _true_section_page(pages, section.number, section.title, outline)
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
    # "(7a)" and "(7b)" are equation 7. Only a page that prints two part
    # letters contributes those spans, matching the detector.
    bare_part = None
    if kind == "equation" and number.isdigit():
        bare_part = re.compile(rf"\(\s*{re.escape(number)}[a-z]\s*\)")
    for page in pages:
        page_patterns = patterns
        if bare_part is not None and number in part_letter_bases(page["text"]):
            page_patterns = [*patterns, bare_part]
        occupied: list[tuple[int, int]] = []
        for pattern in page_patterns:
            for match in pattern.finditer(page["text"]):
                # A list tail captures the number itself. The whole match
                # would also cover the earlier numbers and look like a link
                # to those statements.
                if match.lastindex:
                    start_at, end_at = match.start(match.lastindex), match.end(match.lastindex)
                else:
                    start_at, end_at = match.start(), match.end()
                if any(not (end_at <= start or start_at >= end) for start, end in occupied):
                    continue
                occupied.append((start_at, end_at))
                found.append((page["page_index"], start_at, end_at, page["text"][start_at:end_at]))
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
        outline = None if structure is None else structure.outline
        truth_page = _true_section_page(pages, number, title, outline)
        query = None if structure is None else structural_query(f"what is section {number} about")
        found = None if query is None else locate(query, structure)
        section_cache[number] = truth_page is not None and found is not None and found.start_page == truth_page

    for (kind, number), html_count in sorted(grouped.items()):
        hits = _hits_for(pages, kind, number)
        extraction_misses += max(0, html_count - len(hits))
        for page_index, start, end, surface in hits:
            if _inside(cites.get(page_index, []), start, end):
                # The printed span is a citation. It is a wrong link only when
                # the detector would open an indexed statement there. A
                # suppressed citation is not a local reference, so it is not
                # counted as resolved or missed either.
                covering = [
                    match for match in matches.get(page_index, [])
                    if match.start < end and match.end > start
                ]
                opened = next(
                    (match for match in covering if index.lookup(match.kind, match.number) is not None),
                    None,
                )
                if opened is not None:
                    wrong += 1
                    _add(
                        examples["wrong"],
                        f"p.{page_index + 1} {surface!r} opened {opened.kind} {opened.number} from a citation",
                    )
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
    pdf_verified = []
    rejected_statements = []
    for key, entry in index.entries.items():
        if key in truth.declaration_keys:
            continue
        if entry.kind not in IN_SCOPE and entry.kind not in {"proposition", "corollary", "remark", "example"}:
            continue
        # LaTeXML sometimes drops a numbered statement (a broken counter, or
        # an environment such as {proposition} that it did not expand). The
        # statement is still correct when the PDF prints its heading. An
        # equation or a section has no such heading, and a statement that is
        # in neither place stays a failure.
        if entry.kind in _PDF_HEADING_KINDS:
            heading, mention = _pdf_statement_hits(pages, entry.kind, entry.number)
            if heading is not None:
                pdf_verified.append({
                    "page": entry.page_index + 1,
                    "kind": entry.kind,
                    "number": entry.number,
                    "pdf_page": heading["page_index"] + 1,
                    "pdf_line": heading["line"],
                    "form": heading["form"],
                })
                continue
            rejected_statements.append({
                "page": entry.page_index + 1,
                "kind": entry.kind,
                "number": entry.number,
                "pdf_page": None if mention is None else mention["page_index"] + 1,
                "pdf_line": "" if mention is None else mention["line"],
            })
        false_keys.append(f"p.{entry.page_index + 1} {entry.kind} {entry.number}")
    false_keys.sort()
    pdf_verified.sort(key=lambda item: (item["kind"], _number_sort_key(item["number"]), item["page"]))
    rejected_statements.sort(key=lambda item: (item["kind"], _number_sort_key(item["number"]), item["page"]))

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
        "pdf_verified_declarations": pdf_verified,
        "pdf_verified_count": len(pdf_verified),
        "rejected_statement_declarations": rejected_statements,
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
        heading = "a PDF statement heading" if count == 1 else "PDF statement headings"
        reasons.append(f"{count} indexed {noun} {verb} not in the HTML and {verb} not {heading}")
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
        pages=[
            PageSnapshot(
                page["page_index"],
                page["text"],
                page.get("line_bold") or [],
                page.get("line_italic") or [],
            )
            for page in extracted["pages"]
            if page["text"].strip()
        ],
        page_count=extracted["page_count"],
    )
