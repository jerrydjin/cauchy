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
    is_likely_table_of_contents,
    locate,
    should_index_statements,
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
            parts = all_references("Compare (2.7a) with (2.7b), and ignore (1a).", profile)
            self.assertEqual([(item.kind, item.number) for item in parts], [("equation", "2.7"), ("equation", "2.7")])
            self.assertEqual([item.text for item in parts], ["(2.7a)", "(2.7b)"])
            part = first_reference("from Eq. (3.1c) the bound follows", profile)
            self.assertEqual((part.kind, part.number), ("equation", "3.1"))
            self.assertIsNone(first_reference("The label (1a) is not an equation.", profile))
            figure = first_reference("See Fig. 3a,b for the comparison.", profile)
            self.assertEqual((figure.kind, figure.number), ("figure", "3"))
            self.assertIsNone(first_reference("This is ordinary text.", profile))

    def test_ligature_definition_and_figure(self) -> None:
        # Synthetic. ﬁ is the one character a PDF font uses for "fi".
        heading = "De\ufb01nition 2.1. A widget is a finite set."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(heading, "main")],
            [("definition", "2.1")],
        )
        declared = declaration_matches(heading)
        self.assertEqual([(item.kind, item.number) for item in declared], [("definition", "2.1")])
        mention = "By De\ufb01nition 2.1 every widget is nonempty."
        self.assertEqual(
            [(item.kind, item.number) for item in all_references(mention, "main")],
            [("definition", "2.1")],
        )
        self.assertEqual(declaration_matches(mention), [])
        plural = all_references("De\ufb01nitions 2.1 and 2.2 settle it.", "main")
        self.assertEqual([item.number for item in plural], ["2.1", "2.2"])
        number_first = "6.1 De\ufb01nition. A gadget is a named widget."
        self.assertEqual(
            [(item.kind, item.number) for item in declaration_matches(number_first)],
            [("definition", "6.1")],
        )
        figure = first_reference("See \ufb01gure 4 beside the table.", "main")
        self.assertEqual((figure.kind, figure.number), ("figure", "4"))
        from score import _hits_for  # noqa: E402

        hits = _hits_for([{"page_index": 0, "text": mention}], "definition", "2.1")
        self.assertEqual(hits[0][3].replace("\ufb01", "fi"), "Definition 2.1")

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
            main_hit = first_reference(abbreviated, "main")
            if abbreviated == "Thm 3.2":
                self.assertIsNone(main_hit)
            elif abbreviated.startswith(("Thm", "Lem", "Prop", "Cor", "Def")):
                self.assertIsNotNone(main_hit, abbreviated)
                self.assertEqual((main_hit.kind, main_hit.number), (right.kind, right.number), abbreviated)

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
        abbreviated = first_reference("Thm. 3.2 is abbreviated.", "main")
        self.assertEqual((abbreviated.kind, abbreviated.number), ("theorem", "3.2"))
        self.assertIsNone(first_reference("Thm 3.2 has no period.", "main"))
        listed_abbreviations = all_references("Lem. 2, 3, and 4 finish the argument.", "main")
        self.assertEqual(
            [(item.kind, item.number) for item in listed_abbreviations],
            [("lemma", "2"), ("lemma", "2"), ("lemma", "3"), ("lemma", "4")],
        )
        self.assertEqual(all_references("[12, Thm. 3.2]", "main"), [])
        bare = all_references("The bound lem (11) is the identity (11).", "main")
        self.assertEqual([(item.kind, item.number) for item in bare], [("equation", "11"), ("equation", "11")])
        parenthesized = first_reference("Lem. (4) is parenthesized.", "main")
        self.assertEqual((parenthesized.kind, parenthesized.number), ("lemma", "4"))
        self.assertEqual(first_reference("from Eq. (2.3) it follows", "main").kind, "equation")

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

    def test_a_number_only_tag_uses_the_kind_word_in_the_body(self) -> None:
        # Synthetic. The tag is the counter; "Example" is the first word after it.
        html = """
        <div id="S3">
          <div id="S3.Thmteo16" class="ltx_theorem ltx_theorem_strc">
            <h6 class="ltx_title ltx_title_theorem">
              <span class="ltx_tag ltx_tag_theorem">3.16</span>.
            </h6>
            <p>Example. For the bounded case the lattice is a chain.</p>
          </div>
        </div>
        """
        truth = parse_html(html)
        self.assertEqual(
            [(item.kind, item.number) for item in truth.declarations],
            [("example", "3.16")],
        )

    def test_a_class_kind_and_ligature_use_the_printed_section_number(self) -> None:
        # Synthetic. The tag is "1" and the class says definition. The PDF
        # prints the ligature "Deﬁnition 2.1", which is what the reader indexes.
        html = """
        <section id="S2">
          <div id="Thmproposition1" class="ltx_theorem ltx_theorem_definition">
            <span class="ltx_tag ltx_tag_theorem">1</span>.
            <p>A decorated representation of a knot.</p>
          </div>
          <div id="Thmproposition2" class="ltx_theorem ltx_theorem_lemma">
            <span class="ltx_tag ltx_tag_theorem">2</span>.
            <p>Let the diagram be open.</p>
          </div>
        </section>
        <p>By <a class="ltx_ref" href="#Thmproposition1" title="Definition 1">1</a>.</p>
        """
        truth = parse_html(html)
        use_printed_numbers(
            truth,
            "De\ufb01nition 2.1. A decorated representation of a knot.\n"
            "Lemma 2.2. Let the diagram be open.",
        )
        self.assertEqual(
            [(item.kind, item.number) for item in truth.declarations],
            [("definition", "2.1"), ("lemma", "2.2")],
        )
        self.assertIn(("definition", "2.1"), {(item.kind, item.number) for item in truth.mentions})

    def test_a_local_counter_is_not_restarted_and_a_citation_is_not_the_label(self) -> None:
        # Synthetic. Section 2's HTML numbers are already the local index.
        # "[31, Proposition 6]" is a citation, not proof that the paper prints
        # a bare Proposition 6.
        html = """
        <div id="S2">
          <div id="Thmtheorem2" class="ltx_theorem">
            <span class="ltx_tag ltx_tag_theorem">Definition 2.</span>
          </div>
          <div id="Thmtheorem3" class="ltx_theorem">
            <span class="ltx_tag ltx_tag_theorem">Remark 3.</span>
          </div>
          <div id="Thmtheorem6" class="ltx_theorem">
            <span class="ltx_tag ltx_tag_theorem">Proposition 6.</span>
          </div>
        </div>
        <p>See <a class="ltx_ref" href="#Thmtheorem2" title="Definition 2">2</a>.</p>
        """
        truth = parse_html(html)
        use_printed_numbers(
            truth,
            "Definition 2.2. A system is admissible.\n"
            "Remarks 2.3. (a) Let tau be positive.\n"
            "Proposition 2.6. In Setting 2.1 the operator is bounded.\n"
            "The proof of [31, Proposition 6] adapts.\n",
        )
        self.assertEqual(
            [(item.kind, item.number) for item in truth.declarations],
            [("definition", "2.2"), ("remark", "2.3"), ("proposition", "2.6")],
        )
        self.assertIn(("definition", "2.2"), {(item.kind, item.number) for item in truth.mentions})

    def test_a_line_start_bare_theorem_stays_bare(self) -> None:
        # Synthetic. "Theorem 1." is the printed statement. The definition in
        # the same section uses the restarted section number.
        html = """
        <div id="S3">
          <div id="Thmproposition13" class="ltx_theorem ltx_theorem_definition">
            <span class="ltx_tag ltx_tag_theorem">13</span>
            <p>We call this the action.</p>
          </div>
          <div id="Thmbigtheorem1" class="ltx_theorem">
            <span class="ltx_tag ltx_tag_theorem">Theorem 1.</span>
            <p>Under the hypotheses the sum converges.</p>
          </div>
        </div>
        """
        truth = parse_html(html)
        use_printed_numbers(
            truth,
            "Definition 3.1. We call this the action.\n"
            "Theorem 1. Under the hypotheses the sum converges.\n",
        )
        self.assertEqual(
            {(item.kind, item.number) for item in truth.declarations},
            {("definition", "3.1"), ("theorem", "1")},
        )

    def test_a_real_bare_definition_is_not_renumbered(self) -> None:
        html = """
        <div id="S2">
          <div id="Thmtheorem1" class="ltx_theorem">
            <span class="ltx_tag ltx_tag_theorem">Definition 1.</span>
          </div>
        </div>
        """
        truth = parse_html(html)
        use_printed_numbers(truth, "Definition 1. A set is finite when it is not infinite.\n")
        self.assertEqual(
            [(item.kind, item.number) for item in truth.declarations],
            [("definition", "1")],
        )

    def test_a_bibliography_backref_is_not_a_local_mention(self) -> None:
        # Synthetic. The back-reference list is HTML chrome. Its title can
        # contain the word "equation" without naming an equation, while a
        # theorem named in the bibliography entry itself still counts.
        html = """
        <p>From equation <a class="ltx_ref" href="#S1.E1" title="Equation 1.1">(1.1)</a>.</p>
        <section class="ltx_bibliography">
          <li class="ltx_bibitem">
            See Theorem <a class="ltx_ref" href="#S1.Thmtheorem1" title="Theorem 1.2">1.2</a>.
            <span class="ltx_bibblock ltx_bib_cited">Cited by:
              <a class="ltx_ref" href="#S4.SS3.p1" title="type=equation,Name-sg=Equation, name-sg=equation">§4.3</a>
            </span>
          </li>
        </section>
        """
        truth = parse_html(html)
        mentioned = [(item.kind, item.number) for item in truth.mentions if not item.in_citation]
        self.assertEqual(mentioned, [("equation", "1.1"), ("theorem", "1.2")])

    def test_figure_and_table_anchors_are_not_sections(self) -> None:
        # Synthetic. A float's id hangs off a section (#S2.F1, #S4.T2) and the
        # link text is the float number. A subsubsection id is still a section.
        html = """
        <p>See Section <a class="ltx_ref" href="#S2" title="2 Preliminaries">2</a>,
        <a class="ltx_ref" href="#S2.F1" title="Figure 1">1</a>,
        <a class="ltx_ref" href="#S4.T2" title="Table 2">2</a>,
        and <a class="ltx_ref" href="#S2.SS1.SSS3" title="2.1.3 Details">2.1.3</a>.</p>
        """
        truth = parse_html(html)
        mentioned = [(item.kind, item.number) for item in truth.mentions if not item.in_citation]
        self.assertEqual(mentioned, [("section", "2"), ("section", "2.1.3")])

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

    def test_bare_own_line_fragments_are_not_equations(self) -> None:
        # Synthetic. A split subscript, "(0)" under a one-digit line, and a
        # left-margin wrapped item are not tags. A formula on the next line,
        # a dotted tag, and "(14)" under a one-digit limit stay.
        page = "\n".join([
            "Set f = g before the split.",
            "The expectation of the kernel E[R",
            "(1)",
            "x is at most one, which the hypothesis requires.",
            "L = a + b",
            "(2)",
            "where both terms are positive.",
            "The map sends each point to E",
            "0",
            "(0)",
            "decreases with the energy, as required.",
            "(3)",
            "xn = yn + 1",
            "An ideal containing I.",
            "(4)",
            "Q + 1",
            "The integral equals f = g.",
            "1",
            "(14)",
            "the bound continues below.",
            "The kernel E[R",
            "(8)",
            "x = y + z",
            "(1.4)",
        ])
        positions = {page.index("(4)"): 0.16}
        numbers = [item.number for item in declaration_matches(page, positions)]
        self.assertNotIn("1", numbers)
        self.assertNotIn("0", numbers)
        self.assertNotIn("4", numbers)
        self.assertIn("2", numbers)
        self.assertIn("3", numbers)
        self.assertIn("8", numbers)
        self.assertIn("14", numbers)
        self.assertIn("1.4", numbers)

        unpositioned = [item.number for item in declaration_matches(page)]
        self.assertNotIn("1", unpositioned)
        self.assertNotIn("0", unpositioned)
        self.assertIn("4", unpositioned)

    def test_prose_sentence_does_not_declare_a_bare_equation(self) -> None:
        page = "\n".join([
            "Proof. By construction f = g, so the equivalence between (1) follows at once.",
            "λ = 1 ⇒ (1) and (3)",
            "x = y + z (7)",
            "We minimize the joint loss",
            "L = λ ∑ x",
            "(5)",
            "where the two terms measure energy and force error.",
        ])
        positions = {page.index("(1)"): 0.86}
        numbers = [item.number for item in declaration_matches(page, positions)]
        self.assertNotIn("1", numbers)
        self.assertNotIn("3", numbers)
        self.assertIn("7", numbers)
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

    def test_parenthesized_statement_number_is_not_an_equation(self) -> None:
        text = "Theorem (3.2) gives the bound used in (3.1)."
        for profile in ("main", "hover"):
            matches = all_references(text, profile)
            self.assertEqual(
                [(item.kind, item.number, item.text) for item in matches],
                [("theorem", "3.2", "Theorem (3.2)"), ("equation", "3.1", "(3.1)")],
                profile,
            )
            inside = text.index("(3.2)") + 1
            self.assertEqual(best_reference(text, inside, profile).kind, "theorem")
            self.assertEqual(
                (first_reference("Definition (2.5) names the term.", profile).kind,
                 first_reference("Definition (2.5) names the term.", profile).number),
                ("definition", "2.5"),
            )
            self.assertEqual(all_references("By [12, Theorem (3.2)] the map is continuous.", profile), [])
            self.assertEqual(first_reference("from Eq. (2.3) it follows", profile).kind, "equation")
            self.assertEqual(first_reference("as shown by (1.2)", profile).kind, "equation")

        page = "\n".join([
            "Lemma (4). Suppose the group is finite.",
            "Apply Lemma (4) in the estimate (5).",
            "A = B + C (7)",
        ])
        found = [(item.kind, item.number) for item in declaration_matches(page)]
        self.assertEqual(found.count(("lemma", "4")), 1)
        self.assertIn(("equation", "7"), found)
        self.assertNotIn(("equation", "4"), found)
        self.assertNotIn(("equation", "5"), found)

    def test_line_start_and_number_first_match_the_app(self) -> None:
        page = "\n".join([
            "Theorem 1.1.1",
            "Suppose the sequence of steps is elementary.",
            "Theorem 1.2 shows that the same bound is sharp.",
            "Lemma 2.2, so the order divides the exponent.",
            "Theorem 3.4 The probabilities assigned to the events sum to one.",
            "Theorem 4.1 .... 12",
            "6.1 Definition. A permutation of a set is a bijection onto itself.",
            "8.2 Definition shows the same idea in prose.",
        ])
        found = {(item.kind, item.number) for item in declaration_matches(page)}
        self.assertIn(("theorem", "1.1.1"), found)
        self.assertIn(("theorem", "3.4"), found)
        self.assertIn(("definition", "6.1"), found)
        self.assertNotIn(("theorem", "1.2"), found)
        self.assertNotIn(("lemma", "2.2"), found)
        self.assertNotIn(("theorem", "4.1"), found)
        self.assertNotIn(("definition", "8.2"), found)

    def test_dotted_own_line_tag_does_not_need_a_formula_above_it(self) -> None:
        page = "\n".join([
            "The estimate is recorded below.",
            "(2.4)",
            "where the symbol denotes the usual pairing in the module.",
            "(3)",
            "where the reader may consult the appendix.",
        ])
        numbers = [item.number for item in declaration_matches(page)]
        self.assertIn("2.4", numbers)
        self.assertNotIn("3", numbers)

    def test_dotted_subequation_part_is_the_base_equation(self) -> None:
        page = "\n".join([
            "The two parts of the display are tagged separately.",
            "(4.2a)",
            "(4.2b)",
            "A bare letter on an integer is a label, not an equation.",
            "(1a)",
        ])
        numbers = [item.number for item in declaration_matches(page)]
        self.assertEqual(numbers.count("4.2"), 2)
        self.assertNotIn("1", numbers)
        self.assertFalse(any("a" in number or "b" in number for number in numbers))
        from score import _hits_for  # noqa: E402

        pages = [{"page_index": 0, "text": page}]
        hits = _hits_for(pages, "equation", "4.2")
        self.assertEqual(sorted(item[3] for item in hits), ["(4.2a)", "(4.2b)"])
        self.assertEqual(_hits_for(pages, "equation", "1"), [])

    def test_bare_subequation_family_is_the_base_equation(self) -> None:
        # Synthetic. Two part letters make the base equation; one does not.
        page = "\n".join([
            "Constraints of the model.",
            "(7a)",
            "(7b)",
            "Both tags are the same equation.",
            "Later the text cites (7a) and (7b).",
            "A lone label (1a) is not an equation.",
        ])
        references = [(item.kind, item.number) for item in all_references(page)]
        self.assertEqual(references.count(("equation", "7")), 4)
        self.assertNotIn(("equation", "1"), references)
        numbers = [item.number for item in declaration_matches(page)]
        self.assertEqual(numbers.count("7"), 2)
        self.assertNotIn("1", numbers)
        from score import _hits_for  # noqa: E402

        pages = [{"page_index": 0, "text": page}]
        self.assertEqual(len(_hits_for(pages, "equation", "7")), 4)
        self.assertEqual(_hits_for(pages, "equation", "1"), [])
        solo = "\n".join(["Only one part is printed.", "(7a)", "See (7a) again."])
        self.assertFalse(any(item.number == "7" for item in all_references(solo)))
        self.assertEqual(_hits_for([{"page_index": 0, "text": solo}], "equation", "7"), [])
        factor = "The inequality (a + b) <= (2a)1/q + (2b)1/q holds."
        self.assertFalse(any(item.number == "2" for item in all_references(factor)))


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

    def test_contents_heading_does_not_hide_the_article_on_the_same_page(self) -> None:
        listing = "\n".join([
            "Contents",
            "6.1 Interiors and closures 39",
            "6.2 Limit points 40",
            "7.1 Basic definitions 43",
            "7.2 Complete metric spaces 44",
            "8.1 Connectedness 49",
        ])
        self.assertTrue(is_likely_table_of_contents(listing))
        self.assertFalse(should_index_statements(listing))
        shared = "\n".join([
            "Contents",
            "1",
            "Introduction",
            "2",
            "2",
            "Estimates",
            "4",
            "Let M be a complete manifold of infinite volume with a smooth metric.",
            "The integral of the kernel over the sphere grows as the radius grows.",
            "Theorem 2. Let f be harmonic. Then the integral diverges.",
        ])
        # Heading search still sees a contents page. The statement index does not
        # drop the theorem printed under the list.
        self.assertTrue(is_likely_table_of_contents(shared))
        self.assertTrue(should_index_statements(shared))
        indexed = build_statement_index([{"page_index": 0, "text": shared}], "main")
        self.assertIsNotNone(indexed.lookup("theorem", "2"))

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
                PageSnapshot(3, "1 + w holds over a prime field. Hence the relation is strict."),
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
                PageSnapshot(10, "4. Block-sum\nThe sum is defined here."),
            ],
            page_count=20,
        )
        self.assertEqual(locate(structural_query("what is section 4 about"), clique).start_page, 10)

    def test_a_bold_section_number_on_its_own_line_keeps_the_title(self) -> None:
        structure = Structure(
            outline=[],
            pages=[PageSnapshot(
                2,
                "1.\nIntroduction\nThe argument starts here and is not a heading.",
                [True, True, False],
            )],
            page_count=4,
        )
        found = locate(structural_query("what is section 1 about"), structure)
        self.assertIsNotNone(found)
        self.assertEqual(found.start_page, 2)
        self.assertIn("Introduction", found.label)

    def test_an_italic_subsection_number_on_its_own_line_keeps_the_title(self) -> None:
        structure = Structure(
            outline=[],
            pages=[PageSnapshot(
                4,
                "3.2.\nData assimilation strategy\nThe filter is derived in the following paragraphs.",
                [False, False, False],
                [True, True, False],
            )],
            page_count=6,
        )
        found = locate(structural_query("what is section 3.2 about"), structure)
        self.assertIsNotNone(found)
        self.assertEqual(found.start_page, 4)
        self.assertIn("assimilation", found.label)

    def test_a_numbered_step_on_its_own_line_is_not_a_heading(self) -> None:
        structure = Structure(
            outline=[],
            pages=[PageSnapshot(
                1,
                "3.\nFix an isomorphism of the underlying bundle\nMore prose follows.",
                [False, False, False],
            )],
            page_count=3,
        )
        self.assertIsNone(locate(structural_query("what is section 3 about"), structure))

    def test_a_dotted_number_alone_on_a_line_is_an_equation(self) -> None:
        from cauchy_logic import declaration_matches

        text = (
            "The estimate is recorded below.\n"
            "(2.4)\n"
            "where the symbol denotes the usual pairing in the module."
        )
        found = declaration_matches(text)
        self.assertTrue(any(match.kind == "equation" and match.number == "2.4" for match in found))
        bare = "The cases are listed below.\n(2)\nwhere the reader may consult the appendix."
        bare_found = declaration_matches(bare)
        self.assertFalse(any(match.kind == "equation" and match.number == "2" for match in bare_found))

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
                OutlineNode("2. Linear models", 8),
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
                    OutlineNode("Generator notation", 2),
                ]),
                OutlineNode("Proof of the main result", 5, [
                    OutlineNode("Low degree subspaces", 5),
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


class PluralListScoreTests(unittest.TestCase):
    def test_a_later_number_in_a_plural_list_resolves_on_its_own(self) -> None:
        from ground_truth import Declaration, Mention, PaperTruth, SectionInfo
        from score import score_profile

        truth = PaperTruth(
            mentions=[
                Mention("lemma", "3.1", "named", "Lemmas", False, "Lemmas 3.1, 3.2 and 3.4"),
                Mention("lemma", "3.2", "named", "Lemmas", False, "Lemmas 3.1, 3.2 and 3.4"),
                Mention("lemma", "3.4", "named", "Lemmas", False, "Lemmas 3.1, 3.2 and 3.4"),
            ],
            declarations=[
                Declaration("lemma", "3.1", None, 0),
                Declaration("lemma", "3.2", None, 1),
                Declaration("lemma", "3.4", None, 2),
            ],
            sections=[SectionInfo("1", "Introduction", 1)],
        )
        pages = [{
            "page_index": 0,
            "text": (
                "1. Introduction\n"
                "Lemma 3.1. The first claim is short.\n"
                "Lemma 3.2. The second claim is short.\n"
                "Lemma 3.4. The fourth claim is short.\n"
                "By Lemmas 3.1,\n3.2 and 3.4 the claim follows."
            ),
            "width": 100,
            "blocks": [],
        }]
        card = score_profile(truth, pages, "main", use_structure=False)
        self.assertEqual(card["wrong_links"], 0)
        self.assertEqual(card["missed"], 0)
        self.assertEqual(card["extraction_misses"], 0)
        self.assertGreaterEqual(card["correct"], 3)

    def test_an_unindexed_list_tail_does_not_open_the_first_number(self) -> None:
        from ground_truth import Declaration, Mention, PaperTruth, SectionInfo
        from score import score_profile

        truth = PaperTruth(
            mentions=[
                Mention("theorem", "3.4", "named", "Theorems", False, "Theorems 3.1 and 3.4"),
            ],
            declarations=[Declaration("theorem", "3.1", None, 0)],
            sections=[SectionInfo("1", "Introduction", 1)],
        )
        pages = [{
            "page_index": 0,
            "text": (
                "1. Introduction\n"
                "Theorem 3.1. The first claim is short.\n"
                "Theorems 3.1 and 3.4 remain open."
            ),
            "width": 100,
            "blocks": [],
        }]
        card = score_profile(truth, pages, "main", use_structure=False)
        self.assertEqual(card["wrong_links"], 0)
        self.assertGreaterEqual(card["missed"], 1)


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
