"""The Swift unit cases, checked against the Python port.

Run from the repo root:

    python3 Benchmarks/arxiv_scorecard/test_pipeline.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cauchy_logic import (  # noqa: E402
    OutlineNode,
    PageSnapshot,
    Structure,
    all_references,
    best_reference,
    declaration_matches,
    first_reference,
    locate,
    structural_query,
)


class DetectorTests(unittest.TestCase):
    def test_named_and_equation_cases(self) -> None:
        for profile in ("main", "hover"):
            theorem = first_reference("see Theorem 1.2 for details", profile)
            self.assertEqual((theorem.kind, theorem.number), ("theorem", "1.2"))
            lemma = first_reference("By Lemma 3.4 we obtain", profile)
            self.assertEqual((lemma.kind, lemma.number), ("lemma", "3.4"))
            remark = first_reference("Remark A.0.5. This is an appendix statement.", profile)
            self.assertEqual((remark.kind, remark.number), ("remark", "A.0.5"))
            by_paren = first_reference("as shown by (1.2)", profile)
            self.assertEqual((by_paren.kind, by_paren.number), ("equation", "1.2"))
            eq = first_reference("from Eq. (2.3) it follows", profile)
            self.assertEqual((eq.kind, eq.number), ("equation", "2.3"))
            figure = first_reference("See Fig. 3a,b for the comparison.", profile)
            self.assertEqual((figure.kind, figure.number), ("figure", "3"))
            self.assertIsNone(first_reference("This is ordinary text.", profile))

    def test_figure_ranges(self) -> None:
        text = "Fig. 2 | Results. Later, Figure 2a shows the trend."
        refs = [(item.kind, item.number) for item in all_references(text, "main")]
        self.assertEqual(refs, [("figure", "2"), ("figure", "2")])
        paired = "Figures 1e and 3a,b show the result."
        matches = all_references(paired, "main")
        self.assertEqual([item.number for item in matches], ["1", "3"])
        self.assertEqual([item.text for item in matches], ["Figures 1e", "3a,b"])

    def test_cursor_prefers_the_containing_reference(self) -> None:
        text = "Theorem 1.1 and (1.2)"
        theorem_at = text.index("Theorem")
        equation_at = text.index("(1.2)") + 1
        self.assertEqual(best_reference(text, theorem_at, "main").kind, "theorem")
        self.assertEqual(best_reference(text, equation_at, "main").kind, "equation")

    def test_hover_branch_bibliography_and_abbreviations(self) -> None:
        cited = "[12, Theorem 3.2]"
        self.assertIsNone(first_reference(cited, "main"))
        self.assertIsNone(first_reference(cited, "hover"))
        self.assertEqual(all_references(cited, "hover"), [])
        self.assertIsNone(best_reference(cited, cited.index("Theorem"), "hover"))
        for sample in ("[12, Thm. 3.2]", "[12, Theorems 2.1 and 2.3]", "[see 12, Theorem 3.2]", "[12-14, Theorem 3.2]"):
            self.assertIsNone(first_reference(sample, "hover"), sample)

        text = "Theorem 3.2 improves the bound in [12, Theorem 3.2]."
        matches = all_references(text, "hover")
        self.assertEqual([item.text for item in matches], ["Theorem 3.2"])
        self.assertIsNone(best_reference(text, text.index("[12") , "hover"))
        self.assertEqual(best_reference(text, text.index("Theorem"), "hover").number, "3.2")

        pairs = [
            ("Thm. 3.2", "Theorem 3.2"),
            ("Thm 3.2", "Theorem 3.2"),
            ("Prop. 4.1", "Proposition 4.1"),
            ("Lem. 3.4", "Lemma 3.4"),
            ("Cor. 2.2", "Corollary 2.2"),
            ("Def. 5", "Definition 5"),
            ("Eq. (2.3)", "Equation (2.3)"),
            ("Fig. 3", "Figure 3"),
        ]
        for abbreviated, full in pairs:
            left = first_reference(abbreviated, "hover")
            right = first_reference(full, "hover")
            self.assertIsNotNone(left, abbreviated)
            self.assertEqual((left.kind, left.number), (right.kind, right.number), abbreviated)
            if abbreviated.startswith("Thm"):
                self.assertIsNone(first_reference(abbreviated, "main"))

    def test_hover_plural_lists(self) -> None:
        text = "Theorems 2.1 and 2.3"
        matches = all_references(text, "hover")
        self.assertEqual([item.number for item in matches], ["2.1", "2.3"])
        self.assertEqual([item.text for item in matches], ["Theorems 2.1", "2.3"])
        self.assertEqual(all_references(text, "main"), [])
        for sample in ("Lemmas 3.1, 3.2 and 3.4", "Lemmas 3.1, 3.2, and 3.4"):
            numbers = [item.number for item in all_references(sample, "hover")]
            self.assertEqual(numbers, ["3.1", "3.2", "3.4"], sample)
        for sample in ("Theorems 2.1–2.3", "Theorems 2.1-2.3"):
            numbers = [item.number for item in all_references(sample, "hover")]
            self.assertEqual(numbers, ["2.1", "2.3"], sample)

    def test_main_drops_bracket_and_author_year_citations(self) -> None:
        text = "We refer the reader to [IK99, Lemma 1.15] for a proof. Lemma 2.1."
        references = all_references(text, "main")
        self.assertEqual([(item.kind, item.number) for item in references], [("lemma", "2.1")])
        inside = text.index("Lemma 1.15")
        self.assertIsNone(best_reference(text, inside, "main"))
        local = text.index("Lemma 2.1")
        self.assertEqual(best_reference(text, local, "main").number, "2.1")

        numeric = "By [12, Theorem 3.2] the map is continuous."
        self.assertEqual(all_references(numeric, "main"), [])
        self.assertIsNone(best_reference(numeric, numeric.index("Theorem"), "main"))

        following = "Theorem 3.2 improves the bound in [12, Theorem 3.2]."
        self.assertEqual([item.text for item in all_references(following, "main")], ["Theorem 3.2"])
        self.assertIsNone(best_reference(following, following.index("[12"), "main"))

        for sample in (
            "[CCC+18, Definition 3.5]",
            "[see 12, Theorem 3.2]",
            "[12-14, Theorem 3.2]",
            "[7, proof of Theorem 4.1]",
            "Smith et al. [2019, Lemma 4] proved the bound.",
        ):
            self.assertEqual(all_references(sample, "main"), [], sample)

        parenthetical = "The estimate is due to (Smith 2019)."
        self.assertEqual(all_references(parenthetical, "main"), [])
        self.assertIsNone(best_reference(parenthetical, parenthetical.index("Smith"), "main"))

        # The year bracket does not swallow a statement printed after it.
        after_year = "Smith et al. [2019] proved Lemma 4."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(after_year, "main")],
            [("lemma", "4")],
        )
        self.assertIsNone(best_reference(after_year, after_year.index("2019"), "main"))

        interval = "The interval [0, 1] contains (1)."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(interval, "main")],
            [("equation", "1")],
        )
        self.assertEqual(all_references("Consider the range [1, 2, 3] next.", "main"), [])

        disambiguated = "By [BO09b, Lemma 3.3], the perturbation is small. Lemma 2.1."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(disambiguated, "main")],
            [("lemma", "2.1")],
        )
        self.assertIsNone(best_reference(disambiguated, disambiguated.index("Lemma 3.3"), "main"))
        equation_cite = "Thus wn(t) = M [3, (1.3)]. Since d is faithful, (1.4) follows."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(equation_cite, "main")],
            [("equation", "1.4")],
        )


def _textbook() -> Structure:
    return Structure(
        outline=[
            OutlineNode("Chapter 1. Sets", 0),
            OutlineNode("Chapter 2. Groups", 10, [
                OutlineNode("2.1 Groups", 10),
                OutlineNode("2.2 Actions", 14),
            ]),
            OutlineNode("Chapter 3. Rings", 20),
            OutlineNode("Part II", 40, [OutlineNode("3.4 Fields", 44)]),
            OutlineNode("Part III", 60),
        ],
        pages=[
            PageSnapshot(10, "Chapter 2\nThis chapter studies groups and their actions in detail."),
            PageSnapshot(14, "2.2 Actions\nA group acts on a set when each element gives a permutation."),
            PageSnapshot(36, "Unrelated later material about integrals on pages far from chapter 2."),
        ],
        page_count=80,
    )


class DeclarationTests(unittest.TestCase):
    def test_left_margin_enumerated_steps_are_not_equations(self) -> None:
        page = "\n".join([
            "Proof.",
            "(1) f ∈ W ⇒ f = 0",
            "(2) f ∈ U ⇒ f = 0",
            "(1.10) |x| ≤ r ⇒ |ψ(x)| ≤ r/2.",
            "A = B + C (4) for the constant term.",
            "We minimize the joint loss",
            "L = λ ∑ x",
            "(5)",
            "where the two terms measure energy and force error.",
        ])
        positions = {
            page.index("(1)"): 0.129,
            page.index("(2)"): 0.148,
            page.index("(1.10)"): 0.118,
            page.index("(4)"): 0.82,
        }
        numbers = [item.number for item in declaration_matches(page, positions, "main")]
        self.assertNotIn("1", numbers)
        self.assertNotIn("2", numbers)
        self.assertIn("1.10", numbers)
        self.assertIn("4", numbers)
        self.assertIn("5", numbers)


class StructureTests(unittest.TestCase):
    def test_chapter_section_and_part_from_the_outline(self) -> None:
        query = structural_query("what is chapter 2 about")
        self.assertEqual(query.display_name, "Chapter 2")
        span = locate(query, _textbook())
        self.assertIsNotNone(span)
        self.assertEqual(span.start_page, 10)
        self.assertEqual(span.end_page, 20)
        self.assertEqual(span.label, "Chapter 2. Groups")
        self.assertEqual([item.label for item in span.headings], ["§2.1 Groups", "§2.2 Actions"])

        section = locate(structural_query("explain section 3.4"), _textbook())
        self.assertEqual(section.start_page, 44)
        self.assertEqual(section.end_page, 60)
        self.assertEqual(section.label, "§3.4 Fields")

        part = locate(structural_query("what's in part II"), _textbook())
        self.assertEqual(part.start_page, 40)
        self.assertEqual(part.end_page, 60)
        self.assertEqual(part.label, "Part II")

    def test_roman_heading_and_missing_outline(self) -> None:
        structure = Structure(
            outline=[
                OutlineNode("Chapter II. Groups", 8),
                OutlineNode("Chapter III", 16),
            ],
            pages=[],
            page_count=30,
        )
        span = locate(structural_query("What is chapter 2 about?"), structure)
        self.assertEqual((span.start_page, span.end_page), (8, 16))

        detected = Structure(
            outline=[],
            pages=[
                PageSnapshot(4, "Preface\nHow to read these notes."),
                PageSnapshot(9, "Chapter 2\nGroups begin here with a definition that is long enough to quote."),
                PageSnapshot(18, "Chapter 3\nRings begin after the group theory."),
            ],
            page_count=30,
        )
        span = locate(structural_query("what is ch. 2 about"), detected)
        self.assertEqual((span.start_page, span.end_page), (9, 18))

    def test_contents_page_and_a_numbered_sentence(self) -> None:
        contents = Structure(
            outline=[],
            pages=[PageSnapshot(1, "Contents\n\nChapter 1. Sets .... 1\nChapter 2. Groups .... 15\nChapter 3. Rings .... 40\nAppendix .... 70\nIndex .... 80\n")],
            page_count=90,
        )
        span = locate(structural_query("what is chapter 2 about"), contents)
        self.assertEqual((span.start_page, span.end_page), (14, 39))

        nested = Structure(
            outline=[],
            pages=[PageSnapshot(
                1,
                "Contents\n\nChapter 1. Sets .... 1\nChapter 2. Groups .... 15\n2.1 Groups .... 15\n2.2 Actions .... 22\nChapter 3. Rings .... 40\n",
            )],
            page_count=90,
        )
        span = locate(structural_query("what is chapter 2 about"), nested)
        self.assertEqual((span.start_page, span.end_page), (14, 39))

        sentence = Structure(
            outline=[],
            pages=[
                PageSnapshot(2, "2 Integrals appear here."),
                PageSnapshot(12, "Chapter 2\nGroups begin with a definition long enough to keep."),
                PageSnapshot(20, "Chapter 3\nRings follow the groups."),
            ],
            page_count=30,
        )
        span = locate(structural_query("what is chapter 2 about"), sentence)
        self.assertEqual((span.start_page, span.end_page), (12, 20))

        missing = locate(structural_query("what is chapter 9 about"), _textbook())
        self.assertIsNone(missing)


if __name__ == "__main__":
    unittest.main()
