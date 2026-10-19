"""Ground truth from the arXiv HTML (LaTeXML) rendering.

The HTML has the printed numbers and the link targets. A mention such as
``Lemma <a>2.1</a>`` is a lemma reference; a link inside ``<cite>`` is a
bibliography citation and must not become a local hover target.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from bs4 import BeautifulSoup, NavigableString, Tag


STATEMENT_KINDS = {
    "theorem": "theorem",
    "lemma": "lemma",
    "proposition": "proposition",
    "corollary": "corollary",
    "definition": "definition",
    "remark": "remark",
    "example": "example",
    "exercise": "exercise",
    "proof": "proof",
    "conjecture": "other",
    "claim": "other",
    "hypothesis": "other",
    "assumption": "other",
    "notation": "other",
    "question": "other",
}

IN_SCOPE = {"theorem", "lemma", "definition", "equation", "section"}

_TAG = re.compile(
    r"(?i)^(theorems|lemmas|propositions|corollaries|definitions|remarks|examples|exercises|proofs|"
    r"theorem|lemma|proposition|corollary|definition|remark|example|exercise|proof|"
    r"conjecture|claim|hypothesis|assumption|notation|question)\s+"
    r"([A-Z]?(?:\d+(?:\.\d+)*|\d+)|[A-Z](?:\.\d+)+)\b\.?\s*(?:\(([^)]{1,80})\))?"
)
_TAG_PLURAL = {
    "theorems": "theorem",
    "lemmas": "lemma",
    "propositions": "proposition",
    "corollaries": "corollary",
    "definitions": "definition",
    "remarks": "remark",
    "examples": "example",
    "exercises": "exercise",
    "proofs": "proof",
}
_CUE = re.compile(
    r"(?i)(theorems|lemmas|propositions|corollaries|definitions|remarks|examples|sections|appendices|"
    r"theorem|thm\.?|lemma|lem\.?|proposition|prop\.?|corollary|cor\.?|definition|def\.?|"
    r"remark|example|exercise|proof|section|sec\.?|appendix|eq(?:uation)?\.?|§)\s*$"
)
_NAMED_PAREN = re.compile(
    r"(?i)(theorems|lemmas|propositions|corollaries|definitions|theorem|thm\.?|lemma|lem\.?|"
    r"proposition|prop\.?|corollary|cor\.?|definition|def\.?|remark|section|sec\.?|appendix)\s*\(\s*$"
)
_NUMBER = re.compile(r"[A-Z]?(?:\d+(?:\.\d+)*|\d+)|[A-Z](?:\.\d+)+")
_TITLE_KIND = re.compile(
    r"(?i)^(theorem|lemma|proposition|corollary|definition|remark|example|exercise|proof|"
    r"conjecture|claim)\s+([A-Z]?(?:\d+(?:\.\d+)*))"
)


@dataclass
class Mention:
    kind: str
    number: str
    form: str
    cue: str
    in_citation: bool
    snippet: str
    anchor: str = ""


@dataclass
class Declaration:
    kind: str
    number: str
    name: str | None
    order: int
    anchor: str = ""
    section: str = ""


@dataclass
class SectionInfo:
    number: str
    title: str
    level: int


@dataclass
class PaperTruth:
    mentions: list[Mention] = field(default_factory=list)
    declarations: list[Declaration] = field(default_factory=list)
    sections: list[SectionInfo] = field(default_factory=list)
    citations: list[str] = field(default_factory=list)

    @property
    def declaration_keys(self) -> set[tuple[str, str]]:
        return {(item.kind, item.number) for item in self.declarations}

    @property
    def citation_style(self) -> str:
        styles = set()
        for citation in self.citations:
            if re.search(r"\[\s*\d+", citation):
                styles.add("numeric")
            if re.search(r"\b(?:19|20)\d{2}[a-z]?\b", citation) or re.search(r"\[[A-Z][A-Za-z]+", citation):
                styles.add("author-year")
            if re.search(r"(?i)\b(?:theorem|lemma|proposition|thm|lem|prop)\b", citation):
                styles.add("qualified")
        if not styles:
            return "none"
        return "+".join(sorted(styles))


def _id_matching(node: Tag, pattern: re.Pattern[str]) -> str:
    current: Tag | None = node
    while isinstance(current, Tag):
        identifier = current.get("id") or ""
        if pattern.search(identifier):
            return identifier
        parent = current.parent
        current = parent if isinstance(parent, Tag) else None
    return ""


def _in_toc(node: Tag) -> bool:
    parent = node
    while parent is not None:
        classes = parent.get("class") or []
        if any("ltx_toc" in item or item == "ltx_pagination" for item in classes):
            return True
        if parent.name == "nav":
            return True
        parent = parent.parent if isinstance(parent.parent, Tag) else None
    return False


def _preceding(node: Tag, limit: int = 80) -> str:
    chunks: list[str] = []
    current: Tag | NavigableString | None = node
    while current is not None and sum(len(chunk) for chunk in chunks) < limit:
        previous = current.previous_sibling
        if previous is None:
            parent = current.parent if isinstance(current, Tag) else None
            current = parent if isinstance(parent, Tag) else None
            continue
        current = previous
        if isinstance(current, Tag) and current.name in {"math", "script", "style", "svg"}:
            chunks.append(" ")
            continue
        text = current.get_text(" ", strip=False) if isinstance(current, Tag) else str(current)
        chunks.append(text)
    raw = "".join(reversed(chunks))[-limit:]
    return raw.replace("\xa0", " ").replace("\u2009", " ")


def _snippet(node: Tag) -> str:
    parent = node.parent if isinstance(node.parent, Tag) else node
    text = parent.get_text(" ", strip=True)
    text = re.sub(r"\s+", " ", text)
    return text[:180]


def _kind_number_from_tag(text: str) -> tuple[str, str, str | None] | None:
    found = _TAG.match(text.replace("\xa0", " ").strip())
    if not found:
        return None
    word = found.group(1).lower()
    kind = _TAG_PLURAL.get(word, STATEMENT_KINDS.get(word, "other"))
    return kind, found.group(2), (found.group(3).strip() if found.group(3) else None)


# LaTeXML numbers an enumerated item as #S4.I7.i2 or #S1.I1.ix2. The link
# text is the item number. That is not a section.
_ITEM_HREF = re.compile(r"(?:^|#|\.)(?:I\d+|ix?\d+)(?:\.|$)")


def _target(title: str, href: str, link_text: str) -> tuple[str, str] | None:
    titled = _TITLE_KIND.match(title.replace("\xa0", " ").strip())
    if titled:
        kind = STATEMENT_KINDS.get(titled.group(1).lower(), "other")
        return kind, titled.group(2)
    if re.search(r"\.E\d+\b", href) or "equation" in title.lower():
        number = _NUMBER.search(link_text.replace("\xa0", " "))
        if number:
            return "equation", number.group(0)
    if _ITEM_HREF.search(href):
        return None
    if href.startswith("#S") and ".Thm" not in href and ".E" not in href:
        number = link_text.replace("\xa0", " ").strip().strip(".")
        number = re.sub(r"\s+", "", number)
        if re.fullmatch(r"\d+(?:\.\d+)*|[A-Z]", number):
            return "section", number
    return None


def parse_html(html: str) -> PaperTruth:
    soup = BeautifulSoup(html, "lxml")
    # The annotation is the TeX source beside the rendered math. Reading both
    # turns "SL 2" into "SL 2 \mathrm{SL}_{2}".
    for node in soup.select("script, style, annotation"):
        node.decompose()
    truth = PaperTruth()
    order = 0
    seen_declarations: set[tuple[str, str]] = set()

    for span in soup.select(".ltx_tag_theorem"):
        if not isinstance(span, Tag) or _in_toc(span):
            continue
        parsed = _kind_number_from_tag(span.get_text(" ", strip=True))
        if parsed is None:
            continue
        kind, number, name = parsed
        if kind == "other" or (kind, number) in seen_declarations:
            continue
        if name is None:
            parent = span.find_parent(class_=lambda value: value and any("ltx_title" in item for item in value))
            if isinstance(parent, Tag):
                named = re.search(r"\(([^)]{2,80})\)", parent.get_text(" ", strip=True))
                if named:
                    name = named.group(1).strip()
        seen_declarations.add((kind, number))
        host = span.find_parent(id=re.compile(r"^Thm"))
        anchor = host.get("id") if isinstance(host, Tag) else ""
        section_node = span.find_parent(id=re.compile(r"^S\d+"))
        section = ""
        if isinstance(section_node, Tag):
            found = re.match(r"S(\d+)", section_node.get("id") or "")
            section = found.group(1) if found else ""
        truth.declarations.append(Declaration(kind, number, name, order, anchor or "", section))
        order += 1

    # LaTeXML sometimes prints a remark as a bold run-in, not a theorem tag:
    # <span class="ltx_font_bold">Remark 3.13.</span>
    for span in soup.select("span.ltx_font_bold"):
        if not isinstance(span, Tag) or _in_toc(span) or span.find_parent("cite"):
            continue
        text = re.sub(r"\s+", " ", span.get_text(" ", strip=True)).strip()
        parsed = _kind_number_from_tag(text)
        if parsed is None:
            continue
        kind, number, name = parsed
        if kind == "other" or (kind, number) in seen_declarations:
            continue
        # The span is the label itself. A bold sentence that merely starts
        # with "Theorem 1.1" is not a second declaration.
        label = _TAG.match(text)
        if label is None or label.end() != len(text):
            continue
        seen_declarations.add((kind, number))
        truth.declarations.append(Declaration(kind, number, name, order))
        order += 1

    for span in soup.select(".ltx_tag_equation, .ltx_tag_equationgroup"):
        if not isinstance(span, Tag) or _in_toc(span):
            continue
        number = _NUMBER.search(span.get_text(" ", strip=True).replace("\xa0", " "))
        if number is None:
            continue
        key = ("equation", number.group(0))
        if key in seen_declarations:
            continue
        seen_declarations.add(key)
        anchor = _id_matching(span, re.compile(r"\.E\d+$"))
        truth.declarations.append(Declaration("equation", number.group(0), None, order, anchor))
        order += 1

    for level, selector in (
        (1, ".ltx_title_section, .ltx_title_appendix"),
        (2, ".ltx_title_subsection"),
        (3, ".ltx_title_subsubsection"),
    ):
        for node in soup.select(selector):
            if not isinstance(node, Tag) or _in_toc(node):
                continue
            tag = node.select_one(".ltx_tag_section, .ltx_tag_subsection, .ltx_tag_subsubsection, .ltx_tag_appendix")
            raw_number = tag.get_text(" ", strip=True) if tag else ""
            raw_number = raw_number.replace("\xa0", " ").strip().strip(".")
            raw_number = re.sub(r"(?i)^(?:section|appendix)\s*", "", raw_number).strip()
            title = node.get_text(" ", strip=True)
            if tag:
                title = title.replace(tag.get_text(" ", strip=True), "", 1).strip()
            title = re.sub(r"\s+", " ", title)
            if re.fullmatch(r"\d+(?:\.\d+)*|[A-Z]", raw_number):
                truth.sections.append(SectionInfo(raw_number, title, level))

    seen_cites: set[str] = set()
    for anchor in soup.select("a.ltx_ref"):
        if not isinstance(anchor, Tag) or _in_toc(anchor):
            continue
        href = anchor.get("href") or ""
        if "bib" in href:
            cite = anchor.find_parent("cite")
            text = cite.get_text(" ", strip=True) if isinstance(cite, Tag) else anchor.get_text(" ", strip=True)
            text = re.sub(r"\s+", " ", text)
            if text and text not in seen_cites:
                seen_cites.add(text)
                truth.citations.append(text)
            continue
        cite = anchor.find_parent("cite")
        in_citation = isinstance(cite, Tag)
        if in_citation:
            text = re.sub(r"\s+", " ", cite.get_text(" ", strip=True))
            if text and text not in seen_cites:
                seen_cites.add(text)
                truth.citations.append(text)
        target = _target(anchor.get("title") or "", href, anchor.get_text(" ", strip=True))
        if target is None:
            continue
        kind, number = target
        preceding = _preceding(anchor)
        cue = _CUE.search(preceding.rstrip())
        named_paren = _NAMED_PAREN.search(preceding.rstrip())
        cue_text = (named_paren or cue).group(1) if (named_paren or cue) else ""
        form = "bare"
        # An equation link written after the English word "definition" is still
        # an equation. The cue may change the kind only when the link target
        # itself is a section or otherwise unnamed.
        cue_may_relabel = kind in {"section", "other"}
        if in_citation:
            form = "citation"
        elif cue_text and cue_may_relabel:
            lowered = cue_text.lower().strip(".")
            if lowered in {"section", "sec", "sections"}:
                form = "section_word"
                kind = "section"
            elif lowered == "§":
                form = "section_symbol"
                kind = "section"
            elif lowered in {"appendix", "appendices"}:
                form = "appendix"
                kind = "section"
            elif lowered in {"eq", "equation"}:
                form = "eq_word"
                kind = "equation"
            elif lowered in STATEMENT_KINDS or lowered in {"thm", "lem", "prop", "cor", "def"}:
                mapped = {
                    "thm": "theorem", "lem": "lemma", "prop": "proposition",
                    "cor": "corollary", "def": "definition",
                }.get(lowered, STATEMENT_KINDS.get(lowered, kind))
                if mapped != "other":
                    kind = mapped
                form = "named_paren" if named_paren else (
                    "abbreviation" if lowered in {"thm", "lem", "prop", "cor", "def"} else "named"
                )
        elif kind == "equation":
            form = "eq_word" if cue_text.lower().strip(".") in {"eq", "equation"} else "paren"
        elif cue_text and kind in STATEMENT_KINDS.values():
            lowered = cue_text.lower().strip(".")
            form = "named_paren" if named_paren else (
                "abbreviation" if lowered in {"thm", "lem", "prop", "cor", "def"} else "named"
            )
        if kind == "section" and form == "bare":
            form = "section_word"
        href = anchor.get("href") or ""
        target_id = href[1:] if href.startswith("#") else ""
        truth.mentions.append(Mention(kind, number, form, cue_text, in_citation, _snippet(anchor), target_id))

    return truth


_BARE_NUMBER = re.compile(r"^\d+$")
_EQUATION_ANCHOR = re.compile(r"S(\d+)(?:\.SS\d+)*\.E\d+$")
_STATEMENT_KINDS = {"theorem", "lemma", "proposition", "corollary", "definition", "remark", "example"}


def use_printed_numbers(truth: PaperTruth, pdf_text: str) -> None:
    """LaTeXML sometimes numbers with one counter while the PDF prints section numbers.

    Equation tag ``(1)`` with id ``S1.E1`` is ``(1.1)`` on the page. Remark 1 in
    section 2 is Remark 2.1. Apply this only when every guessed label is printed,
    so a paper that really uses ``(1)`` is left alone.
    """
    _remap_equations(truth, pdf_text)
    _remap_statements(truth, pdf_text)


def _remap_equations(truth: PaperTruth, pdf_text: str) -> None:
    equations = [item for item in truth.declarations if item.kind == "equation" and item.anchor]
    if not equations or any(_BARE_NUMBER.fullmatch(item.number) is None for item in equations):
        return
    groups: dict[str, list[Declaration]] = {}
    for item in equations:
        found = _EQUATION_ANCHOR.search(item.anchor)
        if found is None:
            return
        groups.setdefault(found.group(1), []).append(item)
    planned: dict[str, str] = {}
    for section, items in groups.items():
        for index, item in enumerate(items, start=1):
            printed = f"{section}.{index}"
            if f"({printed})" not in pdf_text:
                return
            planned[item.anchor] = printed
    by_number = {item.number: planned[item.anchor] for item in equations}
    for item in equations:
        item.number = planned[item.anchor]
    for mention in truth.mentions:
        if mention.kind != "equation":
            continue
        if mention.anchor in planned:
            mention.number = planned[mention.anchor]
        elif mention.number in by_number:
            mention.number = by_number[mention.number]


def _remap_statements(truth: PaperTruth, pdf_text: str) -> None:
    statements = [
        item for item in truth.declarations
        if item.kind in _STATEMENT_KINDS and item.anchor.startswith("Thm") and item.section
    ]
    if not statements or any(_BARE_NUMBER.fullmatch(item.number) is None for item in statements):
        return
    groups: dict[str, list[Declaration]] = {}
    for item in statements:
        groups.setdefault(item.section, []).append(item)
    planned: dict[str, str] = {}
    for section, items in groups.items():
        for index, item in enumerate(items, start=1):
            printed = f"{section}.{index}"
            label = f"{item.kind} {printed}"
            if re.search(rf"(?i)\b{re.escape(label)}\b", pdf_text) is None:
                return
            planned[item.anchor] = printed
    for item in statements:
        item.number = planned[item.anchor]
    for mention in truth.mentions:
        if mention.anchor in planned:
            mention.number = planned[mention.anchor]


def shared_counter(declarations: list[Declaration]) -> list[str]:
    """Theorem 2.3 followed by Lemma 2.4, in printed order."""
    examples: list[str] = []
    numbered = []
    for item in declarations:
        if item.kind not in {"theorem", "lemma", "proposition", "corollary"}:
            continue
        parts = item.number.split(".")
        if len(parts) < 2 or not all(part.isdigit() for part in parts):
            continue
        numbered.append((item, parts))
    for (left, left_parts), (right, right_parts) in zip(numbered, numbered[1:]):
        if left.kind == right.kind:
            continue
        if left_parts[:-1] != right_parts[:-1]:
            continue
        if int(right_parts[-1]) == int(left_parts[-1]) + 1:
            examples.append(f"{left.kind.title()} {left.number} then {right.kind.title()} {right.number}")
    return examples
