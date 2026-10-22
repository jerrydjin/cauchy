"""Page text for the scorecard.

PyMuPDF walks the content stream, which is the Linux stand-in for PDFKit's
PDFPage.string. Equation-label x positions are the span's left edge divided
by the page width, the stand-in for PDFKit selection bounds. The reader
dehyphenates hover snippets only, so full-page text is left as extracted.
"""

from __future__ import annotations

import pymupdf

from cauchy_logic import OutlineNode


def _outline_tree(toc: list[list]) -> list[OutlineNode]:
    roots: list[OutlineNode] = []
    stack: list[tuple[int, list[OutlineNode]]] = [(0, roots)]
    for level, title, page in toc:
        node = OutlineNode(title=title or "", page_index=max(page - 1, -1))
        while stack and stack[-1][0] >= level:
            stack.pop()
        stack[-1][1].append(node)
        stack.append((level, node.children))
    return roots


def _page_text_and_positions(page: pymupdf.Page) -> tuple[str, dict[int, float], list[bool], list[bool]]:
    width = page.rect.width or 1.0
    pieces: list[str] = []
    spans: list[tuple[int, int, float]] = []
    line_bold: list[bool] = []
    line_italic: list[bool] = []
    data = page.get_text("dict")
    for block in data.get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            first_flags: int | None = None
            for span in line.get("spans", []):
                text = span.get("text") or ""
                if not text:
                    continue
                start = sum(len(piece) for piece in pieces)
                pieces.append(text)
                spans.append((start, start + len(text), float(span.get("bbox", [0])[0]) / width))
                if first_flags is None and text.strip():
                    first_flags = int(span.get("flags") or 0)
            pieces.append("\n")
            line_bold.append(bool(first_flags is not None and first_flags & 16))
            line_italic.append(bool(first_flags is not None and first_flags & 2))
    raw = "".join(pieces)
    # The trailing newline makes split("\\n") one longer than the visual lines.
    if raw.endswith("\n"):
        line_bold.append(False)
        line_italic.append(False)
    return raw, {start: x for start, _end, x in spans}, line_bold, line_italic


def _equation_positions(text: str, spans: dict[int, float], profile: str) -> dict[int, float]:
    from cauchy_logic import all_references

    positions: dict[int, float] = {}
    if not spans:
        return positions
    keys = sorted(spans)
    for match in all_references(text, profile):
        if match.kind != "equation":
            continue
        # The span that contains the match start. Keys are span starts.
        prior = [key for key in keys if key <= match.start]
        if not prior:
            continue
        positions[match.start] = spans[prior[-1]]
    return positions


def _two_column(page: pymupdf.Page) -> bool:
    width = page.rect.width or 1.0
    # Prose lines in a single column share a left margin. A two-column page
    # also has prose lines that begin near the middle. Equation numbers and
    # the right-hand tail of a display are not prose.
    left = 0
    right = 0
    for block in page.get_text("blocks"):
        if block[6] != 0:
            continue
        letters = sum(char.isalpha() for char in block[4])
        if letters < 40:
            continue
        start = block[0] / width
        if start < 0.18:
            left += 1
        elif start > 0.45:
            right += 1
    return left >= 2 and right >= 2


def extract_pdf(path: str) -> dict:
    document = pymupdf.open(path)
    pages = []
    two_column_pages = 0
    for index, page in enumerate(document):
        text, spans, line_bold, line_italic = _page_text_and_positions(page)
        two_column = _two_column(page)
        if two_column:
            two_column_pages += 1
        pages.append({
            "page_index": index,
            "text": text,
            "span_x": spans,
            "line_bold": line_bold,
            "line_italic": line_italic,
            "two_column": two_column,
        })
    # Equation x depends on which detector profile produced the match offsets.
    # Store span starts and fill positions per profile in the scorer.
    return {
        "page_count": document.page_count,
        "outline": _outline_tree(document.get_toc()),
        "pages": pages,
        "two_column_pages": two_column_pages,
    }


def equation_label_x(page: dict, profile: str) -> dict[int, float]:
    return _equation_positions(page["text"], page.get("span_x") or {}, profile)
