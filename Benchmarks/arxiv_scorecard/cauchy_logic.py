"""Deterministic Cauchy pipeline used by the arXiv scorecard.

This is a line-by-line port of the non-UI rules on main, plus the two open
branches the scorecard compares:

- main: Cauchy/Services/ReferenceParsing.swift, ReferenceDetector.swift,
  LLMReferenceIndexBuilder.declarationMatches, source-fallback indexing.
  Main drops a local hit that sits inside a bracket or author–year citation
  ([12], [IK99, Lemma 1.15], (Smith 2019), Smith et al. [2019]).
- cursor/reference-hover-detection-0cb7: abbreviated, plural, and
  numeric bibliography-qualified references
- cursor/jerry-60-ask-highlight-da7d: AskStructureLocator

PDFKit is not available on Linux. Callers supply page text (PyMuPDF's
content stream is the stand-in for PDFPage.string) and optional equation
label x-fractions (stand-in for PDFKit selection bounds).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


REFERENCE_NUMBER = r"(?:\d+(?:\.\d+)*|[A-Z](?:\.\d+)+)"
SINGULAR_MAIN = r"theorem|lemma|proposition|corollary|definition|exercise|example|remark|proof"
SINGULAR_HOVER = (
    r"theorem|thm\.?|lemma|lem\.?|proposition|prop\.?|corollary|cor\.?|"
    r"definition|def\.?|exercise|example|remark|proof"
)
PLURAL_HOVER = (
    r"theorems|lemmas|propositions|corollaries|definitions|exercises|examples|remarks|proofs"
)
EQUATION = r"(?i)(?:\bby\b|\bsee\b|\bfrom\b|\beq(?:uation)?\.?\s*)?\(\s*(\d+(?:\.\d+)*)\s*\)"
FIGURE = r"(?i)\bfig(?:ure)?\.?\s*(\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?\b"
PAIRED_FIGURES = (
    r"(?i)\b(?:figures|figs\.)\s*((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\s*(?:and|&|,)\s*"
    r"((\d+(?:\.\d+)*)(?:[a-z](?:,[a-z])?)?)\b"
)
BIBLIOGRAPHY_QUALIFIER = re.compile(
    r"\s*(?:see\s+)?\d+(?:\s*[-–—]\s*\d+)?(?:\s*,\s*\d+(?:\s*[-–—]\s*\d+)?)*\s*,\s*"
)
BIBLIOGRAPHY_KEY = r"(?:\d+|[A-Z][A-Za-z]*(?:\+[A-Za-z]*)?\d{2,4}[a-z]?)"
# A citation bracket may be split by the text layer: "[17,\nTheorem 3.31(c)]".
BRACKET_CITATION_BODY = re.compile(r"\[([^\[\]]{1,180})\]")
AUTHOR_YEAR_PARENTHETICAL = re.compile(
    r"\(([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s+((?:19|20)\d{2})\)"
)
AUTHOR_YEAR_BRACKET = re.compile(
    r"([A-Z][A-Za-z'’\-]+)(?:\s+et\s+al\.?)?\s*\[((?:19|20)\d{2})\]"
)
BRACKET_KEY = re.compile(
    rf"^(?:see\s+)?({BIBLIOGRAPHY_KEY})(?:\s*[-–—]\s*\d+)?(?:\s*,\s*(.+))?$"
)

KIND_FROM_KEYWORD = {
    "theorem": "theorem",
    "theorems": "theorem",
    "thm": "theorem",
    "lemma": "lemma",
    "lemmas": "lemma",
    "lem": "lemma",
    "proposition": "proposition",
    "propositions": "proposition",
    "prop": "proposition",
    "corollary": "corollary",
    "corollaries": "corollary",
    "cor": "corollary",
    "definition": "definition",
    "definitions": "definition",
    "def": "definition",
    "exercise": "exercise",
    "exercises": "exercise",
    "example": "example",
    "examples": "example",
    "remark": "remark",
    "remarks": "remark",
    "proof": "proof",
    "proofs": "proof",
}


_MAIN_PLURAL = {
    "theorems": "theorem",
    "lemmas": "lemma",
    "propositions": "proposition",
    "corollaries": "corollary",
    "definitions": "definition",
    "exercises": "exercise",
    "examples": "example",
    "remarks": "remark",
    "proofs": "proof",
}


def kind_for_keyword(keyword: str, profile: str) -> str | None:
    normalized = keyword.lower().strip(".")
    if profile == "main":
        if normalized in {
            "theorem", "lemma", "proposition", "corollary", "definition",
            "exercise", "example", "remark", "proof",
        }:
            return normalized
        return _MAIN_PLURAL.get(normalized)
    return KIND_FROM_KEYWORD.get(normalized)


@dataclass(frozen=True)
class Match:
    kind: str
    number: str
    start: int
    end: int
    text: str

    @property
    def key(self) -> tuple[str, str]:
        return (self.kind, self.number)


@dataclass
class Detection:
    local: list[Match] = field(default_factory=list)
    bibliography_spans: list[tuple[int, int]] = field(default_factory=list)


def _compile(profile: str) -> dict[str, re.Pattern[str]]:
    singular = SINGULAR_MAIN if profile == "main" else SINGULAR_HOVER
    patterns = {
        "named": re.compile(rf"(?i)\b({singular})\s*({REFERENCE_NUMBER})"),
        "equation": re.compile(EQUATION),
        "figure": re.compile(FIGURE),
        "paired": re.compile(PAIRED_FIGURES),
    }
    plural = (
        r"theorems|lemmas|propositions|corollaries|definitions|exercises|examples|remarks|proofs"
        if profile == "main"
        else PLURAL_HOVER
    )
    # Main accepts one number ("Lemmas 4.6") or a list. Hover's list still
    # requires two or more, and hover also accepts abbreviations.
    repeat = "*" if profile == "main" else "+"
    patterns["list"] = re.compile(
        rf"(?i)\b({plural})\s*({REFERENCE_NUMBER}(?:\s*(?:,|and|&|–|—|-)\s*(?:and\s+)?{REFERENCE_NUMBER}){repeat})"
    )
    patterns["number"] = re.compile(REFERENCE_NUMBER)
    return patterns


_PATTERNS = {
    "main": _compile("main"),
    "hover": _compile("hover"),
}


def _overlaps(start: int, end: int, spans: list[tuple[int, int]]) -> bool:
    return any(not (end <= span_start or span_end <= start) for span_start, span_end in spans)


def _external_citation_spans(text: str) -> list[tuple[int, int]]:
    """Spans ReferenceDetector treats as another paper's citation.

    An interval such as "[0, 1]" is not one: the text after the key has to
    contain a letter before the bracket is a qualified citation.
    """
    spans: list[tuple[int, int]] = []
    for found in AUTHOR_YEAR_PARENTHETICAL.finditer(text):
        spans.append((found.start(), found.end()))
    for found in AUTHOR_YEAR_BRACKET.finditer(text):
        if _overlaps(found.start(), found.end(), spans):
            continue
        spans.append((found.start(), found.end()))
    for found in BRACKET_CITATION_BODY.finditer(text):
        if _overlaps(found.start(), found.end(), spans):
            continue
        body = re.sub(r"\s+", " ", found.group(1)).strip()
        match = BRACKET_KEY.fullmatch(body)
        if match is None:
            continue
        qualifier = match.group(2)
        if qualifier is not None:
            # "[0, 1]" is an interval. "[3, (1.3)]" and "[12, Theorem 3.2]" are citations.
            if not any(character.isalpha() for character in qualifier) and "(" not in qualifier:
                continue
        else:
            key = match.group(1)
            # "[2019]" is a year citation. It still owns the bracket, so a
            # local statement is not read out of it.
            if len(key) == 4 and (key.startswith("19") or key.startswith("20")):
                pass
        spans.append((found.start(), found.end()))
    return spans


def _bibliography_span(text: str, start: int, end: int) -> tuple[int, int] | None:
    open_idx = text.rfind("[", 0, start)
    if open_idx < 0:
        return None
    qualifier = text[open_idx + 1 : start]
    if "]" in qualifier:
        return None
    if BIBLIOGRAPHY_QUALIFIER.match(qualifier) is None:
        return None
    close_idx = text.find("]", end)
    if close_idx < 0 or "[" in text[end:close_idx]:
        return None
    return (open_idx, close_idx + 1)


def detection(text: str, profile: str = "main") -> Detection:
    patterns = _PATTERNS[profile]
    raw: list[Match] = []

    for found in patterns["named"].finditer(text):
        kind = kind_for_keyword(found.group(1), profile)
        if kind is None:
            continue
        raw.append(Match(kind, found.group(2), found.start(), found.end(), found.group(0)))

    if "list" in patterns:
        for found in patterns["list"].finditer(text):
            kind = kind_for_keyword(found.group(1), profile)
            if kind is None:
                continue
            list_text = found.group(2)
            list_start = found.start(2)
            for number in patterns["number"].finditer(list_text):
                abs_start = list_start + number.start()
                abs_end = list_start + number.end()
                span_start = found.start() if number.start() == 0 else abs_start
                raw.append(Match(kind, number.group(0), span_start, abs_end, text[span_start:abs_end]))

    for found in patterns["equation"].finditer(text):
        raw.append(Match("equation", found.group(1), found.start(), found.end(), found.group(0)))

    for found in patterns["figure"].finditer(text):
        raw.append(Match("figure", found.group(1), found.start(), found.end(), found.group(0)))

    for found in patterns["paired"].finditer(text):
        raw.append(Match("figure", found.group(2), found.start(), found.end(1), text[found.start() : found.end(1)]))
        raw.append(Match("figure", found.group(4), found.start(3), found.end(3), text[found.start(3) : found.end(3)]))

    if profile == "main":
        spans = _external_citation_spans(text)
        local = [
            match for match in raw
            if not any(start <= match.start and match.end <= end for start, end in spans)
        ]
        local.sort(key=lambda item: (item.start, item.end))
        return Detection(local=local, bibliography_spans=spans)

    local: list[Match] = []
    spans: list[tuple[int, int]] = []
    for match in raw:
        span = _bibliography_span(text, match.start, match.end)
        if span is None:
            local.append(match)
        else:
            spans.append(span)
    local.sort(key=lambda item: (item.start, item.end))
    return Detection(local=local, bibliography_spans=spans)


def all_references(text: str, profile: str = "main") -> list[Match]:
    return detection(text, profile).local


def first_reference(text: str, profile: str = "main") -> Match | None:
    found = all_references(text, profile)
    return found[0] if found else None


def _distance(cursor: int, match: Match) -> int:
    if cursor < match.start:
        return match.start - cursor
    if cursor >= match.end:
        return cursor - match.end
    return 0


def best_reference(text: str, cursor_offset: int, profile: str = "main") -> Match | None:
    found = detection(text, profile)
    if not found.local and not found.bibliography_spans:
        return None
    cursor = max(0, min(cursor_offset, len(text)))
    if any(start <= cursor < end for start, end in found.bibliography_spans):
        return None
    containing = [match for match in found.local if match.start <= cursor < match.end]
    if containing:
        return containing[0]
    if not found.local:
        return None
    return min(found.local, key=lambda match: _distance(cursor, match))


def is_likely_table_of_contents(page_text: str) -> bool:
    lines = [line.strip() for line in page_text.split("\n") if line.strip()]
    if len(lines) < 5:
        return False
    header_words = {"contents", "table of contents", "index"}
    if any(line.lower() in header_words for line in lines[:3]):
        return True
    dot_leaders = re.compile(r"(\.\s*){3,}\d+$")
    numbered = re.compile(r"^\d+(\.\d+)*\.?\s+\D.*\s\d{1,3}$")
    toc_like = sum(1 for line in lines if dot_leaders.search(line) or numbered.search(line))
    return toc_like >= 8 or toc_like / len(lines) >= 0.4


_MATH_SIGNALS = ["=", "≤", "≥", "≠", "≈", "∈", "∉", "⊂", "⊆", "→", "⇒", "∑", "∂", "√", "∞", "∫"]
_DISPLAY_OPERATORS = ["=", "≤", "≥", "≠", "≈", "⇒", "∑", "∫"]
_LABEL_MATH = ["=", "≤", "≥", "≠", "≈", "⇒", "∑", "∫"]
_CITATION_WORDS = ["by", "see", "using", "from", "equation", "eq."]


def _number_extends(number: str, query: str) -> bool:
    """`2` matches `2` and `2.1`, and does not match `20` or `12`."""
    return number == query or number.startswith(query + ".")


def _number_sort_key(number: str) -> list[int | str]:
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", number)]


def _printed_statement_name(text: str, match: Match) -> str | None:
    """Parenthetical printed on the declaration, as in "Lemma 2.4 (Zorn)"."""
    found = re.match(r"\s*\(([^)\n]{2,80})\)", text[match.end : match.end + 120])
    if found is None:
        return None
    name = found.group(1).strip()
    if not name or name[0].isdigit() or not any(character.isalpha() for character in name):
        return None
    if name.lower() not in text.lower():
        return None
    return name


def _offset(text: str, index: int, delta: int) -> int:
    return max(0, min(len(text), index + delta))


def declaration_matches(
    source_text: str,
    equation_label_x: dict[int, float] | None = None,
    profile: str = "main",
) -> list[Match]:
    positions = equation_label_x or {}
    accepted: list[Match] = []
    for match in all_references(source_text, profile):
        after_end = _offset(source_text, match.end, 180)
        before_start = _offset(source_text, match.start, -180)
        after = source_text[match.end : after_end]
        before = source_text[before_start : match.start]
        next_character = next((char for char in after if not char.isspace()), None)
        newline = before.rfind("\n")
        line_start = newline + 1 if newline >= 0 else 0
        prefix = before[line_start:].strip()

        if match.kind == "figure":
            if prefix or not match.text or not match.text[-1].isnumeric():
                continue
            line_end = after.find("\n")
            remainder = after if line_end < 0 else after[:line_end]
            remainder = remainder.strip()
            if not remainder or remainder[0] not in "|:.–—":
                continue
            title = remainder[1:].strip()
            if len(title) >= 8 and any(char.isalpha() for char in title):
                accepted.append(match)
            continue

        if match.kind != "equation":
            if prefix:
                continue
            if next_character in {".", ":", "("}:
                accepted.append(match)
            continue

        line_end = after.find("\n")
        suffix = (after if line_end < 0 else after[:line_end]).strip()
        label_x = positions.get(match.start)
        lower_prefix = prefix.lower()
        if any(lower_prefix.endswith(word) for word in _CITATION_WORDS):
            continue
        if match.start > 0 and not source_text[match.start - 1].isspace():
            continue
        # A bare integer with text to its right is an enumerated proof item,
        # including at the left of the text block. A dotted label such as
        # (1.10), a right-margin label, and a number on its own line stay.
        if match.number.isdigit() and suffix and (label_x is None or label_x < 0.78):
            continue

        if not prefix and not suffix:
            nearby = before[-180:] + after[:180]
        else:
            nearby = prefix + suffix
        if label_x is not None and label_x >= 0.78 and any(op in nearby for op in _DISPLAY_OPERATORS):
            accepted.append(match)
            continue
        if not prefix and suffix and any(op in suffix for op in _MATH_SIGNALS):
            accepted.append(match)
            continue
        if not suffix:
            recent = prefix[-80:]
            if len(prefix.split()) <= 10 and any(op in recent for op in _LABEL_MATH):
                accepted.append(match)
                continue

        matched_text = match.text.strip()
        full_line_start = source_text.rfind("\n", 0, match.start)
        full_line_start = 0 if full_line_start < 0 else full_line_start + 1
        full_line_end = source_text.find("\n", match.end)
        if full_line_end < 0:
            full_line_end = len(source_text)
        full_line = source_text[full_line_start:full_line_end].strip()
        if full_line != matched_text:
            continue
        # A dotted tag alone on a line is the equation number. Enumerated
        # items are bare integers, and a math font often extracts no "=".
        if "." in match.number:
            accepted.append(match)
            continue
        display_start = _offset(source_text, match.start, -600)
        preceding = source_text[display_start : match.start]
        if any(op in preceding for op in _MATH_SIGNALS):
            accepted.append(match)
            continue
        # The formula can sit on the line after the number. A sentence that
        # merely contains "=" is not a display.
        if _following_line_is_display(source_text[match.end :]):
            accepted.append(match)
    return accepted


def _following_line_is_display(rest: str) -> bool:
    lines = rest.split("\n")[1:5]
    next_line = next((line.strip() for line in lines if line.strip()), "")
    if not next_line or not any(op in next_line for op in _DISPLAY_OPERATORS):
        return False
    words = re.findall(r"[A-Za-z]{3,}", next_line)
    return len(words) <= 2


def _fallback_body(source_text: str, match: Match, declarations: list[Match]) -> str | None:
    hard_end = _offset(source_text, match.end, 1600)
    end = hard_end
    for later in declarations:
        if later.kind == "equation":
            continue
        if match.end <= later.start < end:
            end = later.start
            break
    section = re.search(r"(?m)^[ \t]*\d+(?:\.\d+)+\.?[ \t]+[A-Z][^\n]*$", source_text[match.end : end])
    if section:
        end = match.end + section.start()
    window = source_text[match.end : end]
    for marker in ("Proof.", "\nRemark."):
        found = window.lower().find(marker.lower())
        if found >= 0:
            end = match.end + found
            window = source_text[match.end : end]
    body = window.strip()
    if body.startswith(".") or body.startswith(":"):
        body = body[1:].strip()
    return body or None


@dataclass
class IndexedStatement:
    kind: str
    number: str
    page_index: int
    body: str
    name: str | None = None


class StatementIndex:
    """Source-fallback index. The model path is not called.

    Hover only opens a preview when lookup succeeds and the body is non-empty,
    which is the same gate as PDFCanvasView.detectReference.
    """

    def __init__(self) -> None:
        self.entries: dict[tuple[str, str], IndexedStatement] = {}

    def __len__(self) -> int:
        return len(self.entries)

    def lookup(self, kind: str, number: str) -> IndexedStatement | None:
        return self.entries.get((kind, number))

    def add(self, statement: IndexedStatement) -> None:
        key = (statement.kind, statement.number)
        existing = self.entries.get(key)
        if existing is None:
            self.entries[key] = statement
            return
        if statement.page_index < existing.page_index or (
            statement.page_index == existing.page_index and len(statement.body) > len(existing.body)
        ):
            self.entries[key] = statement

    def statements_cited_in(self, text: str, profile: str) -> list[IndexedStatement]:
        seen: set[tuple[str, str]] = set()
        results: list[IndexedStatement] = []
        for match in all_references(text, profile):
            matched = [
                entry for entry in self.entries.values()
                if entry.kind == match.kind
                and _number_extends(entry.number, match.number)
                and entry.body
            ]
            matched.sort(key=lambda entry: _number_sort_key(entry.number))
            for entry in matched:
                key = (entry.kind, entry.number)
                if key in seen:
                    continue
                seen.add(key)
                results.append(entry)
        return results


def build_statement_index(pages: list[dict], profile: str = "main") -> StatementIndex:
    index = StatementIndex()
    for page in pages:
        text = page.get("text") or ""
        if not text.strip() or is_likely_table_of_contents(text):
            continue
        positions = page.get("equation_label_x") or {}
        declarations = declaration_matches(text, positions, profile)
        for match in declarations:
            if match.kind in {"equation", "figure"}:
                body = match.text.strip() or text[max(0, match.start - 80) : match.end + 80].strip()
            else:
                body = _fallback_body(text, match, declarations) or ""
            if not body:
                continue
            if match.kind == "figure":
                name = match.text
            else:
                name = _printed_statement_name(text, match)
            index.add(IndexedStatement(match.kind, match.number, page["page_index"], body, name))
    return index


# --- AskStructureLocator (chat branch) ---------------------------------------

@dataclass
class OutlineNode:
    title: str
    page_index: int
    children: list["OutlineNode"] = field(default_factory=list)


@dataclass
class PageSnapshot:
    page_index: int
    text: str
    # Parallel to text.split("\\n"). A heading number is bold or, for a
    # subsection, italic. The title may end in a math symbol that is not.
    line_bold: list[bool] = field(default_factory=list)
    line_italic: list[bool] = field(default_factory=list)


@dataclass
class Structure:
    outline: list[OutlineNode]
    pages: list[PageSnapshot]
    page_count: int


@dataclass
class StructuralQuery:
    kind: str
    number: str
    canonical: str

    @property
    def display_name(self) -> str:
        label = {"chapter": "Chapter", "section": "Section", "part": "Part"}[self.kind]
        return f"{label} {self.number}"


@dataclass
class Heading:
    title: str
    page_index: int
    label: str


@dataclass
class DocumentSpan:
    label: str
    start_page: int
    end_page: int
    headings: list[Heading]


_CHAPTER_QUERY = re.compile(r"(?i)\b(?:chapter|chap\.?|ch\.?)\s+([0-9]+|[IVXLCDM]+)(?!\.\d)\b")
_PART_QUERY = re.compile(r"(?i)\bpart\s+([0-9]+|[IVXLCDM]+)\b")
_SECTION_QUERY = re.compile(r"(?i)(?:§\s*|(?:section|sec\.?)\s+)(\d+(?:\.\d+)*)(?!\.\d)")
_SECTION_QUERY_BARE = re.compile(r"(?i)\bsection\s+(\d+)(?!\.\d)\b")
_CHAPTER_TITLE = re.compile(r"(?i)^\s*(?:chapter|chap\.?|ch\.?)\s+([0-9]+|[IVXLCDM]+)(?!\.\d)\b")
_PART_TITLE = re.compile(r"(?i)^\s*part\s+([0-9]+|[IVXLCDM]+)\b")
_SECTION_TITLE = re.compile(r"(?i)^\s*(?:§\s*|(?:section|sec\.?)\s+)(\d+(?:\.\d+)*)(?!\.\d)")
_CONTENTS_ENTRY = re.compile(r"^(.{3,90}?)(?:\s*\.{2,}|\s{2,})\s*(\d{1,4})\s*$")
_ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def canonical_number(raw: str) -> str | None:
    token = raw.strip().strip(".")
    if re.fullmatch(r"\d+(?:\.\d+)*", token):
        return token
    value = _roman_value(token)
    if value is None:
        return None
    return str(value)


def _roman_value(token: str) -> int | None:
    letters = token.upper()
    if not letters or any(char not in _ROMAN for char in letters):
        return None
    total = 0
    previous = 0
    for char in reversed(letters):
        value = _ROMAN[char]
        if value < previous:
            total -= value
        else:
            total += value
            previous = value
    return total if 1 <= total <= 40 else None


def structural_query(text: str) -> StructuralQuery | None:
    patterns = [
        ("section", _SECTION_QUERY),
        ("chapter", _CHAPTER_QUERY),
        ("part", _PART_QUERY),
        ("section", _SECTION_QUERY_BARE),
    ]
    best: tuple[int, StructuralQuery] | None = None
    for kind, pattern in patterns:
        found = pattern.search(text)
        if not found:
            continue
        canonical = canonical_number(found.group(1))
        if canonical is None:
            continue
        if best is None or found.start() < best[0]:
            best = (found.start(), StructuralQuery(kind, found.group(1), canonical))
    return None if best is None else best[1]


def _number_in(title: str, pattern: re.Pattern[str]) -> str | None:
    found = pattern.search(title)
    if not found:
        return None
    return canonical_number(found.group(1))


def _leading_number(title: str, dotted: bool) -> str | None:
    pattern = (
        re.compile(r"^\s*§?\s*(\d+(?:\.\d+)+)(?!\.\d)\b")
        if dotted
        else re.compile(r"^\s*(\d+)(?!\.\d)(?:\s|\.(?!\d)|$)")
    )
    return _number_in(title, pattern)


def _leading_roman(title: str) -> str | None:
    return _number_in(title, re.compile(r"^\s*([IVXLCDM]+)(?=\s|\.|$)"))


def _matches_title(title: str, query: StructuralQuery) -> bool:
    if query.kind == "chapter":
        if _number_in(title, _CHAPTER_TITLE) == query.canonical:
            return True
        if title.lower().startswith("part"):
            return False
        return _leading_number(title, dotted=False) == query.canonical or _leading_roman(title) == query.canonical
    if query.kind == "part":
        if _number_in(title, _PART_TITLE) == query.canonical:
            return True
        return _leading_roman(title) == query.canonical
    if _number_in(title, _SECTION_TITLE) == query.canonical:
        return True
    # "9.2 Groups" is section 9.2. "1. Introduction" is section 1.
    # leading_number(dotted=False) rejects a following digit, so "2.1 Title"
    # does not answer section 2.
    return (
        _leading_number(title, dotted=True) == query.canonical
        or _leading_number(title, dotted=False) == query.canonical
    )


# A run-in heading is "2.4. Small cases. Let G be ...". The words after the
# title period are the paragraph, not part of the heading. A sentence that
# happens to be numbered ("2.4. Let us check the axiom. For any x ...") is not.
_SENTENCE_OPENER = re.compile(
    r"(?i)^(let|if|we|suppose|assume|since|then|clearly|hence|thus|therefore|"
    r"now|next|indeed|moreover|however|where|when|because|it|this|note|recall|"
    r"consequently|furthermore|also)\b"
)
_RUN_IN_HEADING = re.compile(
    r"^\s*(\d+(?:\.\d+)+)\.\s+([A-Z][^.=]{1,80}?)\.\s+\S"
)
_NAME_THEN_COMMA = re.compile(r"^[A-Z]\w+\s+[A-Z]\w+,")


def _is_title_line(line: str) -> bool:
    words = line.split()
    if not 1 <= len(words) <= 8:
        return False
    stripped = line.strip()
    if stripped.endswith(("?", "!")):
        return False
    # amsart prints "3.1. From somewhere." The period closes the heading.
    # "2 Integrals appear here." has no period after the opening number.
    if stripped.endswith("."):
        return re.match(r"^\s*\d+(?:\.\d+)*\.\s+\S", line) is not None
    return True


def _run_in_title(line: str) -> str | None:
    """Title prefix of a heading whose paragraph starts on the same line."""
    found = _RUN_IN_HEADING.match(line.strip())
    if found is None:
        return None
    title = found.group(2).strip()
    words = title.split()
    if not 1 <= len(words) <= 12 or _SENTENCE_OPENER.match(title):
        return None
    return f"{found.group(1)}. {title}"


def _long_bare_title(line: str) -> str | None:
    """A heading that is only a title, longer than a short line, with no body.

    "6. Discriminants of minor-free graphs and completable cycles in the plane"
    is one. "2. Ada Lovelace, Notes on the engine" is a bibliography entry.
    """
    stripped = line.strip()
    words = stripped.split()
    if not 9 <= len(words) <= 16:
        return None
    if not re.match(r"^\s*\d+(?:\.\d+)*\.\s+[A-Z]", stripped):
        return None
    if re.search(r"[;:?!=()\[\]]", stripped):
        return None
    rest = re.sub(r"^\s*\d+(?:\.\d+)*\.\s+", "", stripped)
    if _SENTENCE_OPENER.match(rest) or _NAME_THEN_COMMA.match(rest):
        return None
    if stripped.endswith("."):
        return None
    return stripped


_SECTION_NUMBER_LINE = re.compile(r"^(?:§\s*)?(\d+(?:\.\d+){0,2})\.?$")


def _split_heading_title(text: str) -> bool:
    """The line after a bold section number is the title, not a proof step.

    "Introduction" and "Estimating the medium" are titles. "Fix an
    isomorphism" is a sentence, and another number is the next tag.
    """
    stripped = text.strip()
    if not stripped or len(stripped) > 160:
        return False
    if _SECTION_NUMBER_LINE.match(stripped):
        return False
    if not re.match(r"[A-Z]", stripped):
        return False
    words = stripped.split()
    if not 1 <= len(words) <= 16:
        return False
    if not re.search(r"[A-Za-z]{4,}", stripped):
        return False
    if _SENTENCE_OPENER.match(stripped):
        return False
    letters = [char for char in stripped if char.isalpha()]
    if letters and sum(char.isupper() for char in letters) / len(letters) > 0.8 and len(words) <= 6:
        return False
    return True


def logical_lines(
    text: str,
    line_bold: list[bool] | None = None,
    line_italic: list[bool] | None = None,
) -> list[str]:
    """Join an emphasized section number to the title on the next line.

    Many article classes put "1." and "Introduction" on separate visual
    lines, with the number bold and a subsection number italic. A page
    number or an enumerated step is not emphasized on both lines. Emphasis
    is the first glyph, so a math symbol at the end of the title does not
    cancel it.
    """
    raw = text.split("\n")
    if not line_bold and not line_italic:
        return raw
    bold = list(line_bold or []) + [False] * max(0, len(raw) - len(line_bold or []))
    italic = list(line_italic or []) + [False] * max(0, len(raw) - len(line_italic or []))
    joined: list[str] = []
    index = 0
    while index < len(raw):
        line = raw[index].strip()
        number = _SECTION_NUMBER_LINE.match(line)
        emphasized = bold[index] or (italic[index] and number is not None and "." in number.group(1))
        if emphasized and number is not None and 1 <= int(number.group(1).split(".")[0]) <= 40:
            nxt = index + 1
            while nxt < len(raw) and not raw[nxt].strip():
                nxt += 1
            if nxt < len(raw) and (bold[nxt] or italic[nxt]) and _split_heading_title(raw[nxt]):
                tag = line if line.endswith(".") else f"{line}."
                joined.append(f"{tag} {raw[nxt].strip()}")
                index = nxt + 1
                continue
        joined.append(raw[index])
        index += 1
    return joined


def heading_line(line: str) -> str | None:
    """Heading text on this line, or None when the line is prose."""
    stripped = line.strip()
    if not stripped:
        return None
    peeled = _run_in_title(stripped)
    if peeled is not None and _matches_heading_line(peeled):
        return peeled
    long_title = _long_bare_title(stripped)
    if long_title is not None and _opens_with_section_title(long_title):
        return long_title
    if _matches_heading_line(stripped):
        return stripped
    return None


def _title_text_follows(line: str, number: str) -> bool:
    """A heading continues with a capitalised word.

    "1. Introduction" and "4. Block-sum" do. "1 + z", "4 =", and "4 be the" do not.
    """
    rest = re.sub(rf"^\s*(?:§\s*)?{re.escape(number)}\.?\s*", "", line.strip(), count=1)
    return bool(re.match(r"[A-Z]", rest))


def _opens_with_section_title(line: str) -> bool:
    if line.lower().startswith("part"):
        return False
    if _number_in(line, _CHAPTER_TITLE) or _number_in(line, _PART_TITLE) or _number_in(line, _SECTION_TITLE):
        return True
    dotted = _leading_number(line, dotted=True)
    if dotted is not None:
        return _title_text_follows(line, dotted)
    arabic = _leading_number(line, dotted=False)
    if arabic is not None and arabic.isdigit() and 1 <= int(arabic) <= 40:
        return _title_text_follows(line, arabic)
    return _leading_roman(line) is not None


def _matches_heading_line(line: str) -> bool:
    # "Section 4 constructs the metric." is a sentence. The keyword alone
    # does not make it a heading; the line still has to be title-shaped.
    if not _is_title_line(line):
        return False
    return _opens_with_section_title(line)


def _heading_rank(title: str) -> int:
    if re.search(r"(?i)\bpart\b", title):
        return 0
    if re.search(r"(?i)\b(?:chapter|chap\.?|ch\.?)\b", title):
        return 1
    number = _leading_number(title, dotted=True) or _leading_number(title, dotted=False)
    if number:
        return len(number.split(".")) + 1
    return 6


def _display_label(title: str, kind: str | None = None) -> str | None:
    cleaned = re.sub(r"\s*\.{2,}\s*\d*$", "", title).strip()
    if not cleaned:
        return None
    if cleaned.startswith("§"):
        return cleaned
    treat_as_section = kind == "section" or _leading_number(cleaned, dotted=True) is not None
    if treat_as_section and cleaned[:1].isdigit():
        return "§" + cleaned
    return cleaned


_NON_SECTION_TITLE = re.compile(
    r"(?i)^\s*(?:abstract|references|bibliography|acknowledgements?|acknowledgments?|"
    r"contents|table of contents|index|notation)\s*\.?\s*$"
)
_STRUCTURAL_LABEL = re.compile(r"(?i)^\s*(?:chapter|chap\.?|ch\.?|part)\b")


def _explicit_section_number(title: str) -> str | None:
    return (
        _number_in(title, _SECTION_TITLE)
        or _leading_number(title, dotted=True)
        or _leading_number(title, dotted=False)
    )


def _flatten(nodes: list[OutlineNode], depth: int = 0) -> list[tuple[str, int, int]]:
    result: list[tuple[str, int, int]] = []
    for node in nodes:
        if node.page_index >= 0 and node.title.strip():
            result.append((node.title, node.page_index, depth))
        result.extend(_flatten(node.children, depth + 1))
    return result


def _numbered_outline(
    nodes: list[OutlineNode],
    prefix: str | None = None,
    depth: int = 0,
) -> list[tuple[str, str, int, int]]:
    """Outline entries with a section number.

    Bookmarks often read "Introduction" rather than "1. Introduction".
    Those titles are numbered in sibling order, skipping the bibliography
    and chapter labels. A title that already prints its number keeps it.
    """
    entries: list[tuple[str, str, int, int]] = []
    prepared = []
    for node in nodes:
        title = node.title.strip()
        explicit = _explicit_section_number(title) if title else None
        prepared.append((node, title, explicit))
    # "Introduction" beside "1. Preliminaries" is front matter. Invent a
    # number only when none of the siblings already print one.
    any_explicit = any(explicit for _node, _title, explicit in prepared)
    counter = 0
    for node, title, explicit in prepared:
        if node.page_index < 0 or not title:
            entries.extend(_numbered_outline(node.children, prefix, depth + 1))
            continue
        if explicit is None and (
            any_explicit or _NON_SECTION_TITLE.match(title) or _STRUCTURAL_LABEL.match(title)
        ):
            entries.extend(_numbered_outline(node.children, prefix, depth + 1))
            continue
        if explicit is None:
            counter += 1
            number = str(counter) if prefix is None else f"{prefix}.{counter}"
        else:
            number = explicit
            tail = explicit.split(".")[-1]
            if tail.isdigit():
                counter = max(counter, int(tail))
        entries.append((title, number, node.page_index, depth))
        entries.extend(_numbered_outline(node.children, number, depth + 1))
    return entries


def _make_span(
    title: str,
    kind: str,
    start: int,
    end: int,
    page_count: int,
    headings: list[Heading],
) -> DocumentSpan | None:
    if page_count <= 0 or start < 0 or start >= page_count:
        return None
    return DocumentSpan(
        label=_display_label(title, kind) or title,
        start_page=start,
        end_page=min(max(end, start + 1), page_count),
        headings=headings,
    )


def _detected_headings(structure: Structure) -> list[Heading]:
    found: list[Heading] = []
    for page in structure.pages:
        if is_likely_table_of_contents(page.text):
            continue
        for raw in logical_lines(page.text, page.line_bold, page.line_italic):
            # A run-in heading keeps its title and drops the paragraph that
            # follows the title period, so the line can be longer than a title.
            heading = heading_line(raw.strip())
            if heading is None or not 3 <= len(heading) <= 160:
                continue
            found.append(Heading(heading, page.page_index, _display_label(heading) or heading))
    return found


def _span_from_outline(structure: Structure, query: StructuralQuery) -> DocumentSpan | None:
    flat_for_end = _flatten(structure.outline)
    if query.kind == "section":
        numbered = _numbered_outline(structure.outline)
        matches = [
            (title, page, depth)
            for title, number, page, depth in numbered
            if number == query.canonical or _matches_title(title, query)
        ]
    else:
        matches = [item for item in flat_for_end if _matches_title(item[0], query)]
    if not matches:
        return None

    def sort_key(item: tuple[str, int, int]) -> tuple[int, int, int]:
        title, page, depth = item
        kind_hit = 0 if query.kind in title.lower() else 1
        return (kind_hit, depth, page)

    title, page, depth = min(matches, key=sort_key)
    end = structure.page_count
    for other_title, other_page, other_depth in flat_for_end:
        if other_depth <= depth and other_page > page:
            end = other_page
            break
    headings = [
        Heading(other_title, other_page, _display_label(other_title) or other_title)
        for other_title, other_page, other_depth in flat_for_end
        if other_depth > depth and page <= other_page < max(end, page + 1)
    ]
    return _make_span(title, query.kind, page, end, structure.page_count, headings)


def _span_from_headings(structure: Structure, query: StructuralQuery) -> DocumentSpan | None:
    headings = _detected_headings(structure)
    match_index = next((i for i, heading in enumerate(headings) if _matches_title(heading.title, query)), None)
    if match_index is None:
        return None
    match = headings[match_index]
    rank = _heading_rank(match.title)
    later = headings[match_index + 1 :]
    end_heading = next((heading for heading in later if _heading_rank(heading.title) <= rank), None)
    end = structure.page_count if end_heading is None else end_heading.page_index
    nested = [
        heading
        for heading in later
        if heading.page_index < max(end, match.page_index + 1) and _heading_rank(heading.title) > rank
    ]
    return _make_span(match.title, query.kind, match.page_index, end, structure.page_count, nested)


def _contents_entries(structure: Structure) -> list[tuple[str, int]]:
    entries: list[tuple[str, int]] = []
    for page in structure.pages:
        if not is_likely_table_of_contents(page.text):
            continue
        for raw in page.text.split("\n"):
            found = _CONTENTS_ENTRY.match(raw.strip())
            if not found:
                continue
            title = found.group(1).strip()
            if title:
                entries.append((title, int(found.group(2))))
    return entries


def _span_from_contents(structure: Structure, query: StructuralQuery) -> DocumentSpan | None:
    entries = _contents_entries(structure)
    match_index = next((i for i, entry in enumerate(entries) if _matches_title(entry[0], query)), None)
    if match_index is None:
        return None
    title, printed = entries[match_index]
    start = min(max(printed - 1, 0), max(structure.page_count - 1, 0))
    rank = _heading_rank(title)
    later = next((entry for entry in entries[match_index + 1 :] if _heading_rank(entry[0]) <= rank), None)
    if later is None:
        end = min(structure.page_count, start + 8)
    else:
        end = max(start + 1, later[1] - 1)
    return _make_span(title, query.kind, start, end, structure.page_count, [])


def locate(query: StructuralQuery, structure: Structure) -> DocumentSpan | None:
    return (
        _span_from_outline(structure, query)
        or _span_from_headings(structure, query)
        or _span_from_contents(structure, query)
    )


def not_found_message(query: StructuralQuery) -> str:
    return (
        f"{query.display_name} was not found in the outline, headings, or contents. "
        "Highlight a passage or rephrase the question."
    )
