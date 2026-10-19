"""Synthetic fixtures for the arXiv source index. No scorecard paper text."""

from __future__ import annotations

import gzip
import io
import re
import tarfile
import unittest
from pathlib import Path

import pymupdf

from arxiv_id import detect
from latex_source import Unrecognised, build_source_index, parse_latex, unpack_eprint


def _article(*body: str, klass: str = "article") -> str:
    inner = "\n".join(body)
    return (
        "\\documentclass{" + klass + "}\n"
        "\\newtheorem{theorem}{Theorem}[section]\n"
        "\\newtheorem{lemma}[theorem]{Lemma}\n"
        "\\begin{document}\n"
        + inner
        + "\n\\end{document}\n"
    )


class IdTests(unittest.TestCase):
    def test_new_style_stamp_beats_a_different_file_name(self) -> None:
        path = self._pdf("arXiv:2401.01234v3 [math.NT] 2 Jan 2024\nA note.\n", "1999.00001v1.pdf")
        found = detect(path, {"title": "A note"}, Path(path).read_text() if False else _page(path))
        self.assertEqual(found.identifier, "2401.01234")
        self.assertEqual(found.version, "v3")
        self.assertEqual(found.source, "stamp")
        self.assertEqual(found.fetch_id, "2401.01234v3")

    def test_old_style_metadata_and_file_name(self) -> None:
        path = self._pdf("No stamp on this page.\n", "hep-th_9901001v2.pdf")
        found = detect(path, {"subject": "arXiv:math.AG/0601001v1"}, _page(path))
        self.assertEqual(found.identifier, "math.AG/0601001")
        self.assertEqual(found.version, "v1")
        self.assertEqual(found.source, "metadata")

        bare = self._pdf("Nothing.\n", "cond-mat.str-el_0701001.pdf")
        named = detect(bare, {}, _page(bare))
        self.assertEqual(named.identifier, "cond-mat.str-el/0701001")
        self.assertIsNone(named.version)
        self.assertEqual(named.source, "filename")

    def test_version_from_the_file_name_when_the_stamp_omits_it(self) -> None:
        path = self._pdf("arXiv:1501.00001 [math.CO] 1 Jan 2015\n", "1501.00001v4.pdf")
        found = detect(path, {}, _page(path))
        self.assertEqual(found.identifier, "1501.00001")
        self.assertEqual(found.version, "v4")
        self.assertEqual(found.source, "stamp")

    def test_stamp_ignores_a_later_citation(self) -> None:
        text = "arXiv:2101.00001v1 [math.LO] 1 Jan 2021\nSee also arXiv:1999.99999.\n"
        path = self._pdf(text, "unrelated.pdf")
        found = detect(path, {}, _page(path))
        self.assertEqual(found.identifier, "2101.00001")

    def _pdf(self, text: str, name: str) -> str:
        directory = Path(__file__).resolve().parent / "cache" / "fixtures"
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        document = pymupdf.open()
        page = document.new_page()
        page.insert_text((72, 72), text)
        document.save(path)
        document.close()
        return str(path)


def _page(path: str) -> str:
    document = pymupdf.open(path)
    try:
        return document[0].get_text()
    finally:
        document.close()


class UnpackTests(unittest.TestCase):
    def test_gzipped_tex(self) -> None:
        raw = b"\\documentclass{article}\\begin{document}Hi\\end{document}\n"
        files = unpack_eprint(gzip.compress(raw))
        self.assertEqual(set(files), {"main.tex"})
        self.assertIn("documentclass", files["main.tex"])

    def test_tar_gz(self) -> None:
        blob = _tar({"paper.tex": "\\documentclass{article}\n", "macros.tex": "\\newcommand{\\x}{y}\n"})
        files = unpack_eprint(blob)
        self.assertEqual(set(files), {"paper.tex", "macros.tex"})

    def test_pdf_only(self) -> None:
        self.assertIsNone(unpack_eprint(b"%PDF-1.4\n"))
        self.assertIsNone(unpack_eprint(gzip.compress(b"%PDF-1.5\n")))

    def test_garbage_is_unrecognised(self) -> None:
        with self.assertRaises(Unrecognised):
            unpack_eprint(b"this is not an e-print")


class ParseTests(unittest.TestCase):
    def test_shared_counters_starred_sections_and_refs(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\newcommand{\\head}{Lemma}\n"
            "\\newtheorem{theorem}{Theorem}[section]\n"
            "\\newtheorem{lemma}[theorem]{\\head}\n"
            "\\begin{document}\n"
            "\\section{Opening}\n"
            "\\section*{Aside}\n"
            "See Theorem~\\ref{thm:main} and \\eqref{eq:one}.\n"
            "\\cite{alpha}\n"
            "\\section{Body}\n"
            "\\begin{theorem}[Sample]\\label{thm:main}\n"
            "The result holds.\n"
            "\\end{theorem}\n"
            "\\begin{lemma}\\label{lem:next}\n"
            "A consequence.\n"
            "\\end{lemma}\n"
            "\\begin{equation}\\label{eq:one}\n"
            "a=b\n"
            "\\end{equation}\n"
            "\\begin{thebibliography}{9}\n"
            "\\bibitem{alpha} A. Author.\n"
            "\\end{thebibliography}\n"
            "\\end{document}\n"
        )
        sections = [(item.number, item.title) for item in parsed.items if item.role == "section"]
        self.assertEqual(sections, [("1", "Opening"), ("", "Aside"), ("2", "Body")])
        statements = [(item.kind, item.number, item.title) for item in parsed.items if item.role == "statement"]
        self.assertEqual(statements, [("theorem", "2.1", "Sample"), ("lemma", "2.2", "")])
        equations = [item.number for item in parsed.items if item.role == "equation"]
        self.assertEqual(equations, ["1"])
        self.assertEqual(parsed.labels["thm:main"], ("theorem", "2.1"))
        self.assertEqual(parsed.labels["eq:one"], ("equation", "1"))
        self.assertEqual(parsed.refs[0]["target"], ("theorem", "2.1"))
        self.assertEqual(parsed.refs[1]["command"], "eqref")
        self.assertEqual(parsed.refs[1]["target"], ("equation", "1"))
        self.assertEqual(parsed.citations, [["alpha"]])
        self.assertEqual(parsed.bibliography[0].key, "alpha")
        self.assertEqual(parsed.bibliography[0].label, "1")

    def test_amsart_keeps_global_equation_numbers_until_numberwithin(self) -> None:
        parsed = parse_latex(
            _article(
                "\\section{First}",
                "\\begin{equation}a=b\\end{equation}",
                "\\section{Second}",
                "\\begin{equation}c=d\\end{equation}",
                klass="amsart",
            )
        )
        equations = [item.number for item in parsed.items if item.role == "equation"]
        self.assertEqual(equations, ["1", "2"])
        within = parse_latex(
            "\\documentclass{article}\n"
            "\\numberwithin{equation}{section}\n"
            "\\begin{document}\n"
            "\\section{First}\n\\begin{equation}a=b\\end{equation}\n"
            "\\section{Second}\n\\begin{equation}c=d\\end{equation}\n"
            "\\end{document}\n"
        )
        self.assertEqual(
            [item.number for item in within.items if item.role == "equation"],
            ["1.1", "2.1"],
        )

    def test_align_notag_and_subequations(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\begin{document}\n"
            "\\begin{align}\n"
            "a &= b \\label{a} \\\\\n"
            "c &= d \\notag \\\\\n"
            "e &= f \\label{f}\n"
            "\\end{align}\n"
            "\\begin{subequations}\n"
            "\\begin{align}\n"
            "u &= v \\label{u} \\\\\n"
            "w &= x \\label{w}\n"
            "\\end{align}\n"
            "\\end{subequations}\n"
            "\\begin{equation}y=z\\end{equation}\n"
            "\\end{document}\n"
        )
        numbers = [item.number for item in parsed.items if item.role == "equation"]
        self.assertEqual(numbers, ["1", "2", "3a", "3b", "4"])
        self.assertEqual(parsed.labels["f"], ("equation", "2"))
        self.assertEqual(parsed.labels["w"], ("equation", "3b"))

    def test_double_braced_newcommand_name_expands(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\newcommand{{\\wrap}}[1]{#1}\n"
            "\\newtheorem{theorem}{\\wrap{Theorem}}\n"
            "\\begin{document}\n"
            "\\begin{theorem}Holds.\\end{theorem}\n"
            "\\end{document}\n"
        )
        statements = [(item.kind, item.number) for item in parsed.items if item.role == "statement"]
        self.assertEqual(statements, [("theorem", "1")])

    def test_symbol_renewcommand_does_not_abort_the_parse(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\renewcommand\\:\\colon\n"
            "\\newcommand\\eps{\\epsilon}\n"
            "\\newtheorem{theorem}{Theorem}\n"
            "\\begin{document}\n"
            "\\begin{theorem}Holds.\\end{theorem}\n"
            "\\end{document}\n"
        )
        statements = [(item.kind, item.number) for item in parsed.items if item.role == "statement"]
        self.assertEqual(statements, [("theorem", "1")])

    def test_theorem_wrapper_macro_is_not_read_as_a_call(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\newcommand\\theoremwrap[2]{\\newtheorem{#1}[theorem]{#2}}\n"
            "\\newtheorem{theorem}{Theorem}\n"
            "\\theoremwrap{lemma}{Lemma}\n"
            "\\begin{document}\n"
            "\\begin{theorem}First.\\end{theorem}\n"
            "\\begin{lemma}Second.\\end{lemma}\n"
            "\\end{document}\n"
        )
        statements = [(item.kind, item.number) for item in parsed.items if item.role == "statement"]
        self.assertEqual(statements, [("theorem", "1"), ("lemma", "2")])

    def test_input_include_and_cref(self) -> None:
        parsed = parse_latex(
            "\\documentclass{article}\n"
            "\\newtheorem{theorem}{Theorem}\n"
            "\\begin{document}\n"
            "\\input{piece}\n"
            "\\cref{thm:a}\n"
            "\\end{document}\n",
            {"piece.tex": "\\begin{theorem}\\label{thm:a}Text.\\end{theorem}\n"},
        )
        self.assertEqual([(item.kind, item.number) for item in parsed.items if item.role == "statement"], [("theorem", "1")])
        self.assertEqual(parsed.refs[0]["target"], ("theorem", "1"))

    def test_undefined_theorem_and_unknown_format_bail_out(self) -> None:
        with self.assertRaises(Unrecognised):
            parse_latex("\\documentclass{article}\n\\begin{document}\n\\begin{lemma}x\\end{lemma}\n\\end{document}\n")
        with self.assertRaises(Unrecognised):
            parse_latex(
                "\\documentclass{article}\n"
                "\\newtheorem{theorem}{Theorem}\n"
                "\\renewcommand{\\thetheorem}{\\fnsymbol{theorem}}\n"
                "\\begin{document}\\begin{theorem}x\\end{theorem}\\end{document}\n"
            )

    def test_missing_input_bails_out(self) -> None:
        with self.assertRaises(Unrecognised):
            parse_latex("\\documentclass{article}\n\\begin{document}\\input{missing}\\end{document}\n")

    def test_appendix_letter(self) -> None:
        parsed = parse_latex(
            _article("\\section{Main}", "\\appendix", "\\section{Extra}", "\\begin{theorem}x\\end{theorem}")
        )
        sections = [(item.number, item.title) for item in parsed.items if item.role == "section"]
        self.assertEqual(sections, [("1", "Main"), ("A", "Extra")])
        theorem = next(item for item in parsed.items if item.role == "statement")
        self.assertEqual(theorem.number, "A.1")


class MapTests(unittest.TestCase):
    def test_declaration_page_is_used_and_a_miss_is_omitted(self) -> None:
        tex = _article(
            "\\section{Opening}",
            "\\begin{theorem}The result holds for every element.\\end{theorem}",
            "\\begin{equation}a=b\\end{equation}",
            klass="amsart",
        )
        pages = [
            {
                "page_index": 0,
                "text": "See Theorem 1.1 in passing.\n(1) appears in a sentence.\n",
                "span_x": {0: 0.1},
                "two_column": False,
            },
            {
                "page_index": 1,
                "text": "1. Opening\nTheorem 1.1.\nThe result holds for every element.\n(1)\n",
                "span_x": {},
                "two_column": False,
            },
        ]
        # The equation label sits at the right margin of page 1.
        equation_at = pages[1]["text"].rindex("(1)")
        pages[1]["span_x"] = {equation_at: 0.86}
        blob = gzip.compress(tex.encode())
        pdf = _empty_pdf()
        extracted = {"page_count": 2, "outline": [], "pages": pages, "metadata": {}, "two_column_pages": 0}
        built, reason = build_source_index(
            pdf,
            extracted,
            fetcher=lambda arxiv_id: blob,
        )
        self.assertEqual(reason, "latex", reason)
        self.assertIsNotNone(built)
        theorem = built.statement_index.lookup("theorem", "1.1")
        equation = built.statement_index.lookup("equation", "1")
        self.assertIsNotNone(theorem)
        self.assertEqual(theorem.page_index, 1)
        self.assertIsNotNone(equation)
        self.assertEqual(equation.page_index, 1)
        self.assertIsNone(built.statement_index.lookup("theorem", "9.9"))

    def test_repeated_heading_uses_the_statement_words(self) -> None:
        tex = _article("\\section{Opening}", "\\begin{theorem}The result holds for every element.\\end{theorem}")
        pages = [
            {
                "page_index": 0,
                "text": "Theorem 1.1\nA later list repeats the heading without the statement.\n",
                "span_x": {},
                "two_column": False,
            },
            {
                "page_index": 1,
                "text": "Theorem 1.1. The result holds for every element in this chapter.\n",
                "span_x": {},
                "two_column": False,
            },
        ]
        extracted = {"page_count": 2, "outline": [], "pages": pages, "metadata": {}}
        built, reason = build_source_index(
            _empty_pdf(),
            extracted,
            fetcher=lambda _arxiv_id: gzip.compress(tex.encode()),
        )
        self.assertEqual(reason, "latex", reason)
        theorem = built.statement_index.lookup("theorem", "1.1")
        self.assertIsNotNone(theorem)
        self.assertEqual(theorem.page_index, 1)

    def test_mid_line_heading_needs_the_following_words(self) -> None:
        tex = _article("\\section{Opening}", "\\begin{theorem}The result holds for every element.\\end{theorem}")
        pages = [
            {
                "page_index": 0,
                "text": "We cite Theorem 1.1 in the introduction and move on.\n",
                "span_x": {},
                "two_column": False,
            },
            {
                "page_index": 1,
                "text": "As proved below, Theorem 1.1. The result holds for every element.\n",
                "span_x": {},
                "two_column": False,
            },
        ]
        extracted = {"page_count": 2, "outline": [], "pages": pages, "metadata": {}}
        built, reason = build_source_index(
            _empty_pdf(),
            extracted,
            fetcher=lambda _arxiv_id: gzip.compress(tex.encode()),
        )
        self.assertEqual(reason, "latex", reason)
        self.assertEqual(built.statement_index.lookup("theorem", "1.1").page_index, 1)

    def test_equation_follows_its_formula_when_the_number_repeats(self) -> None:
        tex = _article(
            "\\section{Opening}",
            "\\begin{equation}alpha + beta = gamma\\end{equation}",
            klass="amsart",
        )
        pages = [
            _margin_page(0, "delta = epsilon\n(1)\n"),
            _margin_page(1, "The notes mention alpha + beta = gamma in passing.\n\nHeader\n(1)\n"),
            _margin_page(2, "alpha + beta = gamma\n(1)\n"),
        ]
        built = _from_source(tex, pages)
        equation = built.statement_index.lookup("equation", "1")
        self.assertIsNotNone(equation)
        self.assertEqual(equation.page_index, 2)

    def test_repeated_equation_with_the_same_formula_is_omitted(self) -> None:
        tex = _article(
            "\\section{Opening}",
            "\\begin{equation}alpha + beta = gamma\\end{equation}",
            klass="amsart",
        )
        pages = [
            _margin_page(0, "1. Opening\nalpha + beta = gamma\n(1)\n"),
            _margin_page(1, "alpha + beta = gamma\n(1)\n"),
        ]
        built = _from_source(tex, pages)
        self.assertIsNone(built.statement_index.lookup("equation", "1"))

    def test_order_keeps_the_tag_that_precedes_the_next_equation(self) -> None:
        tex = _article(
            "\\section{Opening}",
            "\\begin{equation}ab\\end{equation}",
            "\\begin{equation}delta epsilon zeta\\end{equation}",
            klass="amsart",
        )
        pages = [
            _margin_page(0, "1. Opening\n(1)\n"),
            _margin_page(1, "delta epsilon zeta\n(2)\n"),
            _margin_page(2, "(1)\n"),
        ]
        built = _from_source(tex, pages)
        second = built.statement_index.lookup("equation", "2")
        first = built.statement_index.lookup("equation", "1")
        self.assertIsNotNone(second)
        self.assertEqual(second.page_index, 1)
        self.assertIsNotNone(first)
        self.assertEqual(first.page_index, 0)

    def test_two_in_order_tags_with_no_formula_are_omitted(self) -> None:
        tex = _article(
            "\\section{Opening}",
            "\\begin{equation}ab\\end{equation}",
            "\\begin{equation}delta epsilon zeta\\end{equation}",
            klass="amsart",
        )
        pages = [
            _margin_page(0, "1. Opening\n(1)\n"),
            _margin_page(1, "(1)\n"),
            _margin_page(2, "delta epsilon zeta\n(2)\n"),
        ]
        built = _from_source(tex, pages)
        self.assertEqual(built.statement_index.lookup("equation", "2").page_index, 2)
        self.assertIsNone(built.statement_index.lookup("equation", "1"))

    def test_unlocated_statement_is_left_out(self) -> None:
        tex = _article("\\section{Opening}", "\\begin{theorem}Something.\\end{theorem}")
        pages = [
            {
                "page_index": 0,
                "text": "A page that names neither the heading nor the statement.\n",
                "span_x": {},
                "two_column": False,
            }
        ]
        extracted = {"page_count": 1, "outline": [], "pages": pages, "metadata": {}}
        pdf = _empty_pdf()
        built, reason = build_source_index(pdf, extracted, fetcher=lambda _arxiv_id: gzip.compress(tex.encode()))
        # The section is located and the theorem is not, so the text does not line up.
        self.assertIsNone(built)
        self.assertIn("line up", reason)

    def test_garbage_fetch_does_not_crash(self) -> None:
        pdf = _empty_pdf()
        extracted = {"page_count": 1, "outline": [], "pages": [{"page_index": 0, "text": "arXiv:2401.00001v1 [math.NT] 1 Jan 2024\n", "span_x": {}}], "metadata": {}}
        built, reason = build_source_index(pdf, extracted, fetcher=lambda _arxiv_id: b"not an archive")
        self.assertIsNone(built)
        self.assertTrue(reason)

    def test_pdf_only_submission_falls_back(self) -> None:
        pdf = _empty_pdf()
        extracted = {"page_count": 1, "outline": [], "pages": [{"page_index": 0, "text": "arXiv:2401.00002v1 [math.NT]\n", "span_x": {}}], "metadata": {}}
        built, reason = build_source_index(pdf, extracted, fetcher=lambda _arxiv_id: b"%PDF-1.4")
        self.assertIsNone(built)
        self.assertIn("pdf-only", reason)


def _margin_page(page_index: int, text: str) -> dict:
    spans = {}
    for match in re.finditer(r"\(\d+\)", text):
        spans[match.start()] = 0.86
    return {"page_index": page_index, "text": text, "span_x": spans, "two_column": False}


def _from_source(tex: str, pages: list[dict]):
    extracted = {
        "page_count": len(pages),
        "outline": [],
        "pages": pages,
        "metadata": {},
        "two_column_pages": 0,
    }
    built, reason = build_source_index(
        _empty_pdf(),
        extracted,
        fetcher=lambda _arxiv_id: gzip.compress(tex.encode()),
    )
    if built is None:
        raise AssertionError(reason)
    return built


def _tar(members: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, text in members.items():
            payload = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            archive.addfile(info, io.BytesIO(payload))
    return buffer.getvalue()


def _empty_pdf() -> str:
    directory = Path(__file__).resolve().parent / "cache" / "fixtures"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "2401.00001v1.pdf"
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 36), "arXiv:2401.00001v1 [math.NT] 1 Jan 2024")
    document.save(path)
    document.close()
    return str(path)


if __name__ == "__main__":
    unittest.main()
