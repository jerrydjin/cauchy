"""The Swift unit cases, checked against the Python port.

Run from the repo root:

    python3 Benchmarks/arxiv_scorecard/test_pipeline.py
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ground_truth import parse_html, use_printed_numbers  # noqa: E402
from cauchy_logic import (  # noqa: E402
    IndexedStatement,
    OutlineNode,
    PageSnapshot,
    StatementIndex,
    Structure,
    all_references,
    best_reference,
    build_statement_index,
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
        self.assertEqual([item.number for item in all_references(text, "main")], ["2.1", "2.3"])
        for sample in ("Lemmas 3.1, 3.2 and 3.4", "Lemmas 3.1, 3.2, and 3.4"):
            numbers = [item.number for item in all_references(sample, "hover")]
            self.assertEqual(numbers, ["3.1", "3.2", "3.4"], sample)
        for sample in ("Theorems 2.1–2.3", "Theorems 2.1-2.3"):
            numbers = [item.number for item in all_references(sample, "hover")]
            self.assertEqual(numbers, ["2.1", "2.3"], sample)

    def test_main_plurals_and_short_numbers(self) -> None:
        single = all_references("Lemmas 4.6 and the rest.", "main")
        self.assertEqual([(item.kind, item.number) for item in single], [("lemma", "4.6")])
        definitions = all_references("Definitions 2.5 follow.", "main")
        self.assertEqual([(item.kind, item.number) for item in definitions], [("definition", "2.5")])
        listed = "Lemmas 3.1, 3.2 and 3.4"
        matches = all_references(listed, "main")
        self.assertEqual([item.number for item in matches], ["3.1", "3.2", "3.4"])
        self.assertEqual([item.text for item in matches], ["Lemmas 3.1", "3.2", "3.4"])
        self.assertEqual(all_references("Thm. 3.2 is abbreviated.", "main"), [])

        index = StatementIndex()
        index.add(IndexedStatement("lemma", "2.1", 0, "Let G be finite."))
        index.add(IndexedStatement("lemma", "2.2", 0, "Let G be abelian."))
        index.add(IndexedStatement("lemma", "20", 0, "A different lemma."))
        index.add(IndexedStatement("lemma", "4", 0, "Exactly four."))
        index.add(IndexedStatement("lemma", "4.1", 0, "A child of four."))
        self.assertEqual(
            [item.number for item in index.statements_cited_in("Lemma 2", "main")],
            ["2.1", "2.2"],
        )
        literal = index.statements_cited_in("Lemma 4", "main")
        self.assertIn("4", [item.number for item in literal])
        self.assertIn("4.1", [item.number for item in literal])

        page = "Example 2.3.8 (Hamming distance). Let X = {0, 1}.\n"
        built = build_statement_index([{"page_index": 0, "text": page}], "main")
        stored = built.lookup("example", "2.3.8")
        self.assertIsNotNone(stored)
        self.assertEqual(stored.name, "Hamming distance")

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

        split = "the weak-holomorphy criterion [17,\nTheorem 3.31(c)] shows that G is analytic."
        self.assertEqual(all_references(split, "main"), [], split)
        self.assertEqual(declaration_matches(split, {}, "main"), [])

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


class PrintedNumberTests(unittest.TestCase):
    def test_bare_html_counter_uses_the_printed_section_number(self) -> None:
        html = """
        <div id="S2">
          <div class="ltx_theorem" id="Thmtheorem1">
            <span class="ltx_tag ltx_tag_theorem">Remark 1.</span>
          </div>
        </div>
        <div id="S1">
          <span class="ltx_tag ltx_tag_equation" id="S1.E1">(1)</span>
        </div>
        <p>See <a class="ltx_ref" href="#Thmtheorem1" title="Remark 1">1</a>
        and <a class="ltx_ref" href="#S1.E1" title="Equation 1">(1)</a>.</p>
        """
        truth = parse_html(html)
        use_printed_numbers(truth, "Remark 2.1. The note.\nThe identity (1.1) holds.")
        numbers = {(item.kind, item.number) for item in truth.declarations}
        self.assertIn(("remark", "2.1"), numbers)
        self.assertIn(("equation", "1.1"), numbers)
        mentioned = {(item.kind, item.number) for item in truth.mentions}
        self.assertIn(("remark", "2.1"), mentioned)
        self.assertIn(("equation", "1.1"), mentioned)

    def test_bare_equation_tag_stays_when_the_pdf_prints_it(self) -> None:
        html = """
        <div id="S1"><span class="ltx_tag ltx_tag_equation" id="S1.E1">(1)</span></div>
        <div id="S1"><span class="ltx_tag ltx_tag_equation" id="S1.E2">(2)</span></div>
        <div id="S1"><span class="ltx_tag ltx_tag_equation" id="S1.E3">(3)</span></div>
        """
        truth = parse_html(html)
        use_printed_numbers(truth, "The recurrence (1) implies (2) and (3).")
        self.assertEqual(
            [item.number for item in truth.declarations if item.kind == "equation"],
            ["1", "2", "3"],
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

    def test_own_line_equation_keeps_the_formula_on_the_next_line(self) -> None:
        page = "\n".join([
            "(2)",
            "Then f = 0 whenever the hypothesis holds.",
            "We first consider recurrences of the form",
            "(1)",
            "xn+mxn = P(xn+1, . . . , xn+m-1) =",
            "for n ≥ 0.",
        ])
        numbers = [item.number for item in declaration_matches(page, {}, "main")]
        self.assertIn("1", numbers)
        self.assertNotIn("2", numbers)


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

    def test_math_line_and_prose_are_not_section_headings(self) -> None:
        structure = Structure(
            outline=[],
            pages=[
                PageSnapshot(3, "1 + z7 holds in characteristic 7. Hence the relation is strict."),
                PageSnapshot(4, "Section 4 constructs the approximate metric and solves the nonlinear equation."),
                PageSnapshot(8, "1. Introduction\nThe algebra is introduced here and used below."),
                PageSnapshot(11, "4. Approximate solutions\nThe metric is built in this section."),
            ],
            page_count=20,
        )
        section1 = locate(structural_query("what is section 1 about"), structure)
        self.assertEqual(section1.start_page, 8)
        section4 = locate(structural_query("what is section 4 about"), structure)
        self.assertEqual(section4.start_page, 11)

        clique = Structure(
            outline=[],
            pages=[
                PageSnapshot(4, "4 be the\n4 ="),
                PageSnapshot(10, "4. Clique-sum\nThe sum is defined here."),
            ],
            page_count=20,
        )
        self.assertEqual(locate(structural_query("what is section 4 about"), clique).start_page, 10)

    def test_run_in_heading_keeps_the_title_and_drops_the_paragraph(self) -> None:
        structure = Structure(
            outline=[],
            pages=[PageSnapshot(
                4,
                "2.4. Small cases. Let G be a graph with four vertices and one cycle.\n"
                "The rest of the page is ordinary prose about matrices.",
            )],
            page_count=8,
        )
        found = locate(structural_query("what is section 2.4 about"), structure)
        self.assertIsNotNone(found)
        self.assertEqual(found.start_page, 4)
        self.assertIn("Small cases", found.label)
        self.assertNotIn("graph", found.label.lower())

    def test_numbered_proof_sentence_is_not_a_run_in_heading(self) -> None:
        structure = Structure(
            outline=[],
            pages=[PageSnapshot(
                1,
                "2.4. Let us check the first axiom. For any x and y the product stays inside.",
            )],
            page_count=4,
        )
        self.assertIsNone(locate(structural_query("what is section 2.4 about"), structure))

    def test_long_title_is_a_heading_and_a_bibliography_line_is_not(self) -> None:
        titled = Structure(
            outline=[],
            pages=[PageSnapshot(
                2,
                "6. Discriminants of minor-free graphs and completable cycles in the plane\n"
                "Ordinary text follows on the next line and is not a heading.",
            )],
            page_count=5,
        )
        found = locate(structural_query("what is section 6 about"), titled)
        self.assertEqual(found.start_page, 2)

        bibliography = Structure(
            outline=[],
            pages=[PageSnapshot(
                0,
                "2. Ada Lovelace, Notes on the analytic engine and its design",
            )],
            page_count=3,
        )
        self.assertIsNone(locate(structural_query("what is section 2 about"), bibliography))

    def test_a_parent_bookmark_does_not_answer_a_subsection_with_the_same_title(self) -> None:
        from score import _true_section_page

        pages = [
            {"page_index": 3, "text": "2. Shared title\nThe parent section starts here with enough prose."},
            {"page_index": 5, "text": "2.2. Shared title\nThe subsection starts on this later page."},
        ]
        outline = [OutlineNode("2. Shared title", 3)]
        self.assertEqual(_true_section_page(pages, "2.2", "Shared title", outline), 5)
        self.assertEqual(_true_section_page(pages, "2", "Shared title", outline), 3)

    def test_numbered_sibling_keeps_its_number_beside_introduction(self) -> None:
        structure = Structure(
            outline=[
                OutlineNode("Introduction", 0),
                OutlineNode("1. Preliminaries", 4),
                OutlineNode("2. Affine realizations", 8),
            ],
            pages=[],
            page_count=20,
        )
        self.assertEqual(locate(structural_query("what is section 1 about"), structure).start_page, 4)
        self.assertEqual(locate(structural_query("what is section 2 about"), structure).start_page, 8)

    def test_unnumbered_outline_bookmarks_are_sections_in_order(self) -> None:
        structure = Structure(
            outline=[
                OutlineNode("Introduction", 0),
                OutlineNode("Preliminaries", 2, [
                    OutlineNode("Virasoro notation", 2),
                ]),
                OutlineNode("Proof of the main result", 5, [
                    OutlineNode("Low homogeneous subspaces", 5),
                ]),
                OutlineNode("References", 12),
            ],
            pages=[],
            page_count=16,
        )
        self.assertEqual(locate(structural_query("what is section 1 about"), structure).start_page, 0)
        self.assertEqual(locate(structural_query("what is section 2 about"), structure).start_page, 2)
        self.assertEqual(locate(structural_query("what is section 3 about"), structure).start_page, 5)
        self.assertEqual(locate(structural_query("what is section 3.1 about"), structure).start_page, 5)
        self.assertIsNone(locate(structural_query("what is section 4 about"), structure))


class CitationScoreTests(unittest.TestCase):
    def test_suppressed_citation_is_not_a_wrong_link(self) -> None:
        from ground_truth import Declaration, Mention, PaperTruth, SectionInfo
        from score import score_profile

        truth = PaperTruth(
            mentions=[
                Mention("lemma", "1.15", "citation", "Lemma", False, "[IK99, Lemma 1.15]"),
                Mention("lemma", "2.1", "local", "Lemma", False, "Lemma 2.1"),
            ],
            declarations=[Declaration("lemma", "2.1", None, 0)],
            sections=[SectionInfo("1", "Introduction", 1)],
        )
        pages = [{
            "page_index": 0,
            "text": "See [IK99, Lemma 1.15] for the proof.\n1. Introduction\nLemma 2.1. The statement is short.",
            "width": 100,
            "blocks": [],
        }]
        # equation_label_x looks at blocks; an empty page still scores.
        card = score_profile(truth, pages, "main", use_structure=False)
        self.assertEqual(card["wrong_links"], 0)
        self.assertEqual(card["citation_detections"], 0)

    def test_a_citation_split_across_a_line_is_not_a_missed_local_reference(self) -> None:
        from ground_truth import Declaration, Mention, PaperTruth, SectionInfo
        from score import score_profile

        truth = PaperTruth(
            mentions=[
                Mention("theorem", "1.1", "named", "Theorem", False, "Theorem 1.1"),
                Mention("theorem", "2.2", "named", "Theorem", False, "Theorem 2.2"),
            ],
            declarations=[
                Declaration("theorem", "1.1", None, 0),
                Declaration("theorem", "2.2", None, 1),
            ],
            sections=[SectionInfo("1", "Introduction", 1)],
        )
        pages = [{
            "page_index": 0,
            "text": "See [Zho23,\nTheorem 1.1] for the model.\n1. Introduction\nTheorem 2.2. The local statement is short.",
            "width": 100,
            "blocks": [],
        }]
        card = score_profile(truth, pages, "main", use_structure=False)
        self.assertEqual(card["citation_detections"], 0)
        self.assertEqual(card["wrong_links"], 0)
        self.assertEqual(card["missed"], 0)
        self.assertGreaterEqual(card["correct"], 1)


class HtmlReferenceTests(unittest.TestCase):
    def test_enumerated_item_link_is_not_a_section(self) -> None:
        html = """
        <p>See (<a class="ltx_ref" href="#S4.I1.i2" title="item 2">2</a>)
        and <a class="ltx_ref" href="#S3" title="3. Tracially AF algebras">3</a>
        and <a class="ltx_ref" href="#S2.SS1.p1.1" title="2.1 Basics">2.1</a>.</p>
        """
        truth = parse_html(html)
        sections = {(item.kind, item.number) for item in truth.mentions if item.kind == "section"}
        self.assertNotIn(("section", "2"), sections)
        self.assertIn(("section", "3"), sections)
        self.assertIn(("section", "2.1"), sections)

    def test_math_annotation_is_not_part_of_the_heading(self) -> None:
        html = """
        <h4 class="ltx_title ltx_title_subsubsection">
          <span class="ltx_tag ltx_tag_subsubsection">2.1. </span>
          Subgroups of
          <math alttext="\\mathrm{SL}_{2}" class="ltx_Math">
            <semantics>
              <msub><mi>SL</mi><mn>2</mn></msub>
              <annotation encoding="application/x-tex">\\mathrm{SL}_{2}</annotation>
            </semantics>
          </math>
        </h4>
        """
        truth = parse_html(html)
        self.assertEqual(len(truth.sections), 1)
        self.assertNotIn("mathrm", truth.sections[0].title)
        self.assertIn("SL", truth.sections[0].title)


if __name__ == "__main__":
    unittest.main()
