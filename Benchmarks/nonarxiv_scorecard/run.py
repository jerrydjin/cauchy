"""Score freely licensed, non-arXiv PDFs with the PDF heuristics only.

Each document is a chapter-sized slice. Expected labels were read from the PDF
text layer: a declaration is a line that begins with the label (or, in Doty's
numbering, with the number and then the label). A following lowercase word, or
a comma, is a mention of that label, not another declaration. An equation
number ends a line or is the whole line. Section pages are numbered outline
bookmarks, or a line that is only the section number followed by a heading. A
following line that is only a number is a plot tick. Resolution alone is the
printed theorem, lemma, definition, and equation spans. The source path is off.
Nothing here is an arXiv e-print.

    python3 Benchmarks/nonarxiv_scorecard/run.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / "cache"
SCORECARD = ROOT / "scorecard.json"
JSON_OUT = ROOT.parent / "results" / "2026-10-19-nonarxiv-source-off.json"
sys.path.insert(0, str(ROOT.parent / "arxiv_scorecard"))

from cauchy_logic import OutlineNode, Structure, PageSnapshot, build_statement_index  # noqa: E402
from ground_truth import Declaration, Mention, PaperTruth, SectionInfo  # noqa: E402
from pdf_extract import equation_label_x, extract_pdf  # noqa: E402
from score import _hits_for, attach_structure, make_structure, score_profile  # noqa: E402

# 1-indexed inclusive PDF pages. Ranges sit on the chapters whose labels were read.
CORPUS = [
    {
        "id": "doty-permutation-groups",
        "file": "doty-abstract-algebra.pdf",
        "title": "Doty, Abstract Algebra, permutation groups",
        "area": "algebra",
        "form": "textbook chapter",
        "license": "CC BY 4.0",
        "url": "https://doty.math.luc.edu/abstract-alg.pdf",
        "pages": [22, 35],
        "number_first": True,
    },
    {
        "id": "judson-groups",
        "file": "judson-aata.pdf",
        "title": "Judson, Abstract Algebra, groups",
        "area": "algebra",
        "form": "textbook chapter",
        "license": "GFDL 1.2",
        "url": "https://judsonbooks.org/aata-files/aata-20220728.pdf",
        "pages": [40, 70],
    },
    {
        "id": "lebl-sequences",
        "file": "lebl-real-analysis.pdf",
        "title": "Lebl, Basic Analysis, sequences",
        "area": "analysis",
        "form": "textbook chapter",
        "license": "CC BY-SA 4.0",
        "url": "https://www.jirka.org/ra/realanal.pdf",
        "pages": [51, 84],
    },
    {
        "id": "lebl-holomorphic",
        "file": "lebl-complex.pdf",
        "title": "Lebl, Guide to Complex Variables, holomorphic functions",
        "area": "complex analysis",
        "form": "textbook chapter",
        "license": "CC BY-NC-SA 4.0",
        "url": "https://www.jirka.org/ca/ca.pdf",
        "pages": [26, 51],
    },
    {
        "id": "lebl-first-order",
        "file": "lebl-diffyqs.pdf",
        "title": "Lebl, Notes on Diffy Qs, first-order equations",
        "area": "differential equations",
        "form": "textbook chapter",
        "license": "CC BY-SA 4.0",
        "url": "https://www.jirka.org/diffyqs/diffyqs.pdf",
        "pages": [21, 56],
    },
    {
        "id": "nicholson-systems",
        "file": "nicholson-lawa.pdf",
        "title": "Nicholson, Linear Algebra with Applications, systems",
        "area": "linear algebra",
        "form": "textbook chapter",
        "license": "CC BY-NC-SA 4.0",
        "url": "https://math.sci.ccny.cuny.edu/document/Nicholson-Linear+Algebra+with+Applications2018.pdf",
        "pages": [21, 47],
    },
    {
        "id": "kuttler-determinants",
        "file": "kuttler-fcla.pdf",
        "title": "Kuttler, A First Course in Linear Algebra, determinants",
        "area": "linear algebra",
        "form": "textbook chapter",
        "license": "CC BY 4.0",
        "url": "https://openlab.citytech.cuny.edu/poiriermat2580fall2024/files/2024/01/Kuttler-LinearAlgebra-AFirstCourse.pdf",
        "pages": [123, 155],
    },
    {
        "id": "treil-bases",
        "file": "treil-ladw.pdf",
        "title": "Treil, Linear Algebra Done Wrong, bases and matrices",
        "area": "linear algebra",
        "form": "textbook chapter",
        "license": "CC BY-NC-ND 3.0",
        "url": "https://www.math.brown.edu/~treil/papers/LADW/LADW_2017-09-04.pdf",
        "pages": [11, 40],
    },
    {
        "id": "ntic-division",
        "file": "ntic.pdf",
        "title": "Crisman, Number Theory in Context, division",
        "area": "number theory",
        "form": "textbook chapter",
        "license": "CC BY-ND 4.0",
        "url": "https://math.gordon.edu/ntic/nticoneside.pdf",
        "pages": [32, 50],
    },
    {
        "id": "grinstead-probability",
        "file": "grinstead-snell-probability.pdf",
        "title": "Grinstead and Snell, Introduction to Probability, discrete distributions",
        "area": "probability",
        "form": "textbook chapter",
        "license": "GFDL",
        "url": "https://math.dartmouth.edu/~prob/prob/prob.pdf",
        "pages": [20, 45],
    },
    {
        "id": "guichard-derivative",
        "file": "guichard-calculus.pdf",
        "title": "Guichard, Calculus, rules for derivatives",
        "area": "calculus",
        "form": "textbook chapter",
        "license": "CC BY-NC-SA",
        "url": "https://www.whitman.edu/mathematics/calculus/calculus.pdf",
        "pages": [55, 90],
    },
    {
        "id": "levin-counting",
        "file": "levin-dmoi.pdf",
        "title": "Levin, Discrete Mathematics, counting",
        "area": "discrete mathematics",
        "form": "textbook chapter",
        "license": "CC BY-SA",
        "url": "https://discrete.openmathbooks.org/pdfs/dmoi-tablet.pdf",
        "pages": [17, 70],
    },
    {
        "id": "mcs-number-theory",
        "file": "mcs.pdf",
        "title": "Lehman, Leighton, Meyer, Mathematics for Computer Science, number theory",
        "area": "number theory",
        "form": "textbook chapter",
        "license": "CC BY-SA 4.0",
        "url": "https://courses.csail.mit.edu/6.042/spring18/mcs.pdf",
        "pages": [349, 390],
    },
    {
        "id": "keller-binomial",
        "file": "app-comb.pdf",
        "title": "Keller and Trotter, Applied Combinatorics, binomial coefficients",
        "area": "combinatorics",
        "form": "textbook chapter",
        "license": "CC BY-SA 4.0",
        "url": "https://appliedcombinatorics.org/book-pdf/app-comb-2017.pdf",
        "pages": [41, 70],
    },
    {
        "id": "open-logic-sets",
        "file": "open-logic.pdf",
        "title": "Open Logic Project, naive set theory",
        "area": "logic",
        "form": "textbook chapter",
        "license": "CC BY 4.0",
        "url": "https://builds.openlogicproject.org/open-logic-complete.pdf",
        "pages": [26, 57],
    },
    {
        "id": "forallx-arguments",
        "file": "forallxyyc.pdf",
        "title": "forall x Calgary, key notions of logic",
        "area": "logic",
        "form": "textbook chapter",
        "license": "CC BY 4.0",
        "url": "https://forallx.openlogicproject.org/forallxyyc.pdf",
        "pages": [12, 78],
    },
]

_HEAD = r"theorem|lemma|proposition|corollary|definition|remark|example"
_EQ_END = re.compile(r"\(([0-9]+(?:\.[0-9]+)+)\)\s*$")
_EQ_ONLY = re.compile(r"^\(([0-9]+(?:\.[0-9]+)+)\)\s*$")
_LABEL_FIRST = re.compile(rf"(?i)^(?:{_HEAD})\s+([0-9]+(?:\.[0-9]+)*)\b(.*)$")
_NUMBER_FIRST = re.compile(rf"(?i)^([0-9]+(?:\.[0-9]+)+)\s+({_HEAD})\b(.*)$")
_KIND = {
    "theorem": "theorem",
    "lemma": "lemma",
    "proposition": "proposition",
    "corollary": "corollary",
    "definition": "definition",
    "remark": "remark",
    "example": "example",
}


def _slice(extracted: dict, start: int, end: int) -> dict:
    """`start` and `end` are 1-indexed inclusive PDF pages."""
    pages = []
    for page in extracted["pages"]:
        if start - 1 <= page["page_index"] <= end - 1:
            copied = dict(page)
            copied["page_index"] = page["page_index"] - (start - 1)
            pages.append(copied)
    outline = _shift_outline(extracted["outline"], start - 1, end - 1)
    return {
        "pages": pages,
        "outline": outline,
        "page_count": len(pages),
        "two_column_pages": sum(1 for page in pages if page.get("two_column")),
        "metadata": extracted.get("metadata") or {},
    }


def _shift_outline(nodes: list, first: int, last: int) -> list[OutlineNode]:
    shifted: list[OutlineNode] = []
    for node in nodes:
        children = _shift_outline(node.children, first, last)
        if first <= node.page_index <= last:
            shifted.append(OutlineNode(node.title, node.page_index - first, children))
        else:
            shifted.extend(children)
    return shifted


def _declaration_lines(pages: list[dict], number_first: bool) -> list[dict]:
    found: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for page in pages:
        for raw in (page.get("text") or "").splitlines():
            line = " ".join(raw.split())
            if not line or line.lower().startswith("proof of"):
                continue
            kind = number = rest = None
            numbered = _NUMBER_FIRST.match(line) if number_first else None
            labeled = _LABEL_FIRST.match(line)
            if numbered:
                number, kind, rest = numbered.group(1), numbered.group(2).lower(), numbered.group(3)
            elif labeled:
                kind, number, rest = labeled.group(0).split()[0].lower(), labeled.group(1), labeled.group(2)
                kind = _KIND[kind]
            else:
                continue
            rest = rest or ""
            if rest.lstrip().startswith(")"):
                continue
            tail = rest.lstrip()
            if tail.startswith("("):
                close = tail.find(")")
                tail = tail[close + 1 :] if close >= 0 else ""
                tail = tail.lstrip(" .:")
            # "Lemma 9.1.2, so the order..." cites a clause. It is not a declaration.
            if tail and tail[0] in ",;":
                continue
            if tail and tail[0].islower():
                continue
            key = (_KIND.get(kind, kind), number)
            if key in seen:
                continue
            seen.add(key)
            found.append({
                "kind": key[0],
                "number": number,
                "page": page["page_index"],
                "how": "The PDF text layer has a line that begins with this label.",
            })
    return found


def _is_statement_word(word: str) -> bool:
    token = word.lower().rstrip(".:")
    return token in set(_HEAD.split("|")) or token in {"exercise", "exercises", "problem", "note", "proof"}


def _is_heading_title(title: str) -> bool:
    """A heading is not a figure caption or the continuation of a sentence."""
    words = title.split()
    if not words:
        return False
    if words[0].lower().rstrip(".:") in {"figure", "fig", "table"}:
        return False
    if words[0][:1].islower():
        return False
    return True


def _sections(sliced: dict) -> list[dict]:
    found: list[dict] = []
    seen: set[str] = set()

    def add(number: str, title: str, page: int, how: str) -> None:
        if number in seen or not title:
            return
        seen.add(number)
        found.append({
            "number": number,
            "title": title.strip(" ."),
            "level": 1 if "." not in number else 2,
            "page": page,
            "how": how,
        })

    def walk(nodes: list) -> None:
        for node in nodes:
            match = re.match(r"^\s*(\d+(?:\.\d+)*)\b", node.title or "")
            if match and node.page_index >= 0:
                title = re.sub(r"^\s*\d+(?:\.\d+)*\s*", "", node.title or "").strip(" .")
                if title and not _is_statement_word(title.split()[0]) and _is_heading_title(title):
                    add(match.group(1), title, node.page_index, "PDF outline bookmark whose title starts with this number.")
            walk(node.children)

    walk(sliced["outline"])
    if len(found) >= 2:
        return found
    found.clear()
    seen.clear()
    for page in sliced["pages"]:
        lines = [" ".join(raw.split()) for raw in (page.get("text") or "").splitlines()]
        lines = [line for line in lines if line]
        for index, line in enumerate(lines):
            split = re.match(r"^(\d+(?:\.\d+))$", line)
            if split is None or index + 1 >= len(lines):
                continue
            title = lines[index + 1]
            if _is_statement_word(title.split()[0]) or not _is_heading_title(title):
                continue
            # A slope-field axis prints "0.0" and then "2.5". That is not a heading.
            if re.fullmatch(r"-?\d+(?:\.\d+)?", title):
                continue
            if len(title) > 80:
                continue
            add(split.group(1), title, page["page_index"], "The section number is alone on a line and the next line is the heading.")
    return found


def _equations(pages: list[dict]) -> list[dict]:
    """A displayed equation number sits at the end of a line or on its own line.

    `(1)` at the start of a line is an enumeration, not an equation, and is omitted.
    """
    found: list[dict] = []
    seen: set[str] = set()
    for page in pages:
        for raw in (page.get("text") or "").splitlines():
            line = " ".join(raw.split())
            match = _EQ_END.search(line) or _EQ_ONLY.match(line)
            if match is None:
                continue
            if line.startswith("(") and not _EQ_ONLY.match(line):
                continue
            number = match.group(1)
            if number in seen:
                continue
            seen.add(number)
            found.append({
                "kind": "equation",
                "number": number,
                "page": page["page_index"],
                "how": "A line in the chapter ends with this parenthesized number, or is only that number.",
            })
    return found


def _truth(declarations: list[dict], sections: list[dict]) -> PaperTruth:
    truth = PaperTruth()
    for order, item in enumerate(declarations):
        truth.declarations.append(Declaration(item["kind"], item["number"], None, order))
        truth.mentions.append(Mention(
            item["kind"], item["number"], "named", item["kind"], False,
            f"{item['kind']} {item['number']}",
        ))
    for item in sections:
        truth.sections.append(SectionInfo(item["number"], item["title"], item["level"], item["page"]))
        if item["number"].count(".") <= 1:
            truth.mentions.append(Mention("section", item["number"], "section_word", "section", False, f"section {item['number']}"))
    return truth


def _printed_resolution(pages: list[dict], index, declarations: list[dict]) -> dict:
    """Resolution of printed in-scope spans. A label the page never prints is not a reference."""
    correct = missed = 0
    for item in declarations:
        if item["kind"] not in {"theorem", "lemma", "definition", "equation"}:
            continue
        hits = _hits_for(pages, item["kind"], item["number"])
        for _page, _start, _end, _surface in hits:
            if index.lookup(item["kind"], item["number"]) is not None:
                correct += 1
            else:
                missed += 1
    printed = correct + missed
    rate = None if printed == 0 else correct / printed
    return {"printed": printed, "correct": correct, "missed": missed, "rate": rate}


def _real_sections(sections: list[dict]) -> list[dict]:
    return [item for item in sections if not re.fullmatch(r"-?\d+(?:\.\d+)?", item["title"])]


def _calibrate(printed: dict, sections: list[dict], main: dict) -> dict:
    """Which pass-bar checks a chapter slice can answer, and which failure group it is in.

    The minimum of 8 and the section question do not apply to every slice. Resolution
    is the fraction of printed theorem, lemma, definition, and equation spans.
    """
    count = printed["printed"]
    rate = printed["rate"]
    real = _real_sections(sections)
    resolution_applies = count > 0
    minimum_applies = count >= 8
    section_applies = len(real) > 0
    resolution_low = resolution_applies and rate is not None and rate < 0.90
    # (a) resolution is not the failure. (b) a fair slice, and resolution is low.
    # (c) resolution is low and the slice also lacks either 8 refs or a numbered section.
    if not resolution_low:
        group = "a"
    elif minimum_applies and section_applies:
        group = "b"
    else:
        group = "c"
    return {
        "group": group,
        "resolution_alone": None if rate is None else round(rate, 4),
        "printed_in_scope_refs": count,
        "checks": {
            "resolution": resolution_applies,
            "minimum_of_8": minimum_applies,
            "section_question": section_applies,
            "wrong_link": True,
            "citation_as_local_ref": True,
            "false_declaration": True,
        },
    }


def _score_record(record: dict) -> dict:
    extracted = extract_pdf(str(CACHE / record["file"]))
    start, end = record["pages"]
    sliced = _slice(extracted, start, end)
    declarations = _declaration_lines(sliced["pages"], record.get("number_first", False))
    declarations.extend(_equations(sliced["pages"]))
    sections = _sections(sliced)
    truth = _truth(declarations, sections)
    structure = make_structure(sliced)
    attach_structure(structure)
    main = score_profile(truth, sliced["pages"], "main", True)
    prepared = [{**page, "equation_label_x": equation_label_x(page, "main")} for page in sliced["pages"]]
    printed = _printed_resolution(sliced["pages"], build_statement_index(prepared, "main"), declarations)
    return {
        "id": record["id"],
        "title": record["title"],
        "area": record["area"],
        "form": record["form"],
        "license": record["license"],
        "url": record["url"],
        "pdf_pages": record["pages"],
        "source_path": {"mode": "pdf", "reason": "flag off"},
        "declarations": declarations,
        "sections": sections,
        "calibration": _calibrate(printed, sections, main),
        "profiles": {"main": main},
    }


def main() -> None:
    rows = [_score_record(record) for record in CORPUS]
    payload = {
        "latex_source": False,
        "method": (
            "Sixteen chapter slices from freely licensed PDFs that are not arXiv "
            "e-prints. Licenses were read from the PDF's opening pages. Each "
            "expected declaration is a text-layer line that begins with the label; "
            "a following lowercase word is a mention, not a second declaration. "
            "Doty prints the number before the label. An equation number either "
            "ends a line or is the whole line. A comma after the number "
            "(\"Lemma 2.2, so\") is a mention, not a declaration. Section pages are "
            "numbered outline bookmarks when the PDF has them, and otherwise a line "
            "that contains only the section number followed by a heading. A following "
            "line that is itself only a number is a plot tick. A figure caption, or a "
            "bookmark whose first word is lowercase, is not a heading. "
            "Resolution alone counts printed theorem, lemma, definition, and equation "
            "spans. The minimum of 8 applies when there are at least 8 of those spans. "
            "The section question applies when the slice has a numbered heading. "
            "The source path is off. Journal PDFs from Discrete Analysis responded "
            "with an empty body, so this set is books."
        ),
        "papers": rows,
    }
    JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUT.write_text(json.dumps(payload, indent=2) + "\n")
    public = []
    for row in rows:
        main = row["profiles"]["main"]
        public.append({
            "id": row["id"],
            "title": row["title"],
            "area": row["area"],
            "form": row["form"],
            "license": row["license"],
            "url": row["url"],
            "pdf_pages": row["pdf_pages"],
            "how": payload["method"],
            "declarations": row["declarations"],
            "sections": [{k: item[k] for k in ("number", "title", "level", "page", "how")} for item in row["sections"]],
            "calibration": row["calibration"],
            "main": {
                "passes": main["passes"],
                "resolution_rate": main["resolution_rate"],
                "denominator": main["denominator"],
                "correct": main["correct"],
                "missed": main["missed"],
                "extraction_misses": main["extraction_misses"],
                "wrong_links": main["wrong_links"],
                "citation_detections": main["citation_detections"],
                "false_declaration_count": main["false_declaration_count"],
                "false_declarations": main["false_declarations"],
                "section_questions_ok": main["section_questions"]["ok"],
                "fail_reasons": main["fail_reasons"],
            },
        })
    SCORECARD.write_text(json.dumps({"method": payload["method"], "papers": public}, indent=2) + "\n")
    passed = sum(item["main"]["passes"] for item in public)
    print(f"NON-ARXIV main {passed}/{len(public)}")
    for item in public:
        main = item["main"]
        print(
            f"{item['id']} pass={main['passes']} rate={main['resolution_rate']:.0%} "
            f"den={main['denominator']} false={main['false_declaration_count']} "
            f"cite={main['citation_detections']} sec={main['section_questions_ok']} "
            f"decls={len(item['declarations'])}"
        )
        cal = item["calibration"]
        print(
            f"  group={cal['group']} alone={cal['resolution_alone']} "
            f"printed={cal['printed_in_scope_refs']} checks={cal['checks']}"
        )
        if main["fail_reasons"]:
            print("  ", "; ".join(main["fail_reasons"])[:180])


if __name__ == "__main__":
    main()
