"""The scanned set is its own score and is not a release gate.

    python3 Benchmarks/arxiv_scorecard/test_scanned.py
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scanned import classify_extraction, counts_toward_release_gate, load_ids  # noqa: E402

ROOT = Path(__file__).resolve().parent


def _page(index: int, text: str) -> dict:
    return {
        "page_index": index,
        "text": text,
        "span_x": {},
        "line_bold": [],
        "line_italic": [],
        "two_column": False,
    }


def _extracted(pages: list[dict]) -> dict:
    return {"page_count": len(pages), "outline": [], "pages": pages, "two_column_pages": 0}


class ScannedSetTests(unittest.TestCase):
    def test_the_set_is_not_a_release_gate_and_is_not_in_the_dev_ids(self) -> None:
        scanned = load_ids()
        self.assertFalse(scanned["counts_toward_release_gate"])
        self.assertGreaterEqual(len(scanned["papers"]), 3)
        self.assertLessEqual(len(scanned["papers"]), 5)
        scanned_ids = {paper["id"] for paper in scanned["papers"]}
        for name in ("ids.json", "dev_ids_wide.json"):
            payload = json.loads((ROOT / name).read_text())
            dev_ids = {paper["id"] for paper in payload.get("papers", [])}
            dev_ids.update(paper["id"] for paper in payload.get("edge_cases", []) or [])
            self.assertTrue(scanned_ids.isdisjoint(dev_ids))
        for paper in scanned["papers"]:
            self.assertTrue(paper["source_url"].startswith("https://"))
            self.assertTrue(paper["license"])

    def test_a_blank_scan_is_no_text_layer_and_does_not_pass(self) -> None:
        pages = [_page(index, "") for index in range(8)]
        pages.append(_page(8, "This is a digital copy of a book that was preserved for generations on library shelves."))
        card = classify_extraction(_extracted(pages))
        self.assertEqual(card["failure_modes"], ["no text layer"])
        self.assertFalse(card["passes"])
        self.assertFalse(counts_toward_release_gate({"counts_toward_release_gate": False, **card}))

    def test_garbled_equation_labels_are_broken_reference_detection(self) -> None:
        text = (
            "( 129 )\n"
            "NOTE ON CLAPEYRON'S THEOREM OF THE THREE MOMENTS.\n"
            "By Karl Pearson.\n"
            "(1) Clapeyron in a paper published in the Comptes rendus, T. XLV., (1857), "
            "pp. 1076-80, has shown that the following relation holds between the moments "
            "at three successive points of support of a continuous beam.\n"
        )
        card = classify_extraction(_extracted([_page(0, text)]))
        self.assertIn("broken reference detection", card["failure_modes"])
        self.assertNotIn("no text layer", card["failure_modes"])
        self.assertFalse(card["passes"])
        self.assertGreater(card["references"]["in_scope"], 0)
        self.assertLess(card["references"]["resolution_rate"], 0.90)

    def test_a_split_chapter_heading_is_wrong_section_resolution(self) -> None:
        chapter = (
            "CHAPTER\n"
            "I\n"
            "FROM ARITHMETIC TO ALGEBRA\n"
            "Arithmetic means dealing logically with facts which we know about questions of number.\n"
        )
        later = "1 D. Marks bases the Seventh Commandment on\n"
        filler = "The following pages discuss hypotheses, sewing cards, and the limits of a teacher's function.\n"
        pages = [_page(0, chapter), _page(1, filler), _page(2, later)]
        card = classify_extraction(
            _extracted(pages),
            [{"number": "1", "title": "From arithmetic to algebra", "page": 1}],
        )
        self.assertIn("wrong section resolution", card["failure_modes"])
        probed = card["sections"]["probed"][0]
        self.assertEqual(probed["expected_page"], 1)
        self.assertEqual(probed["predicted_page"], 3)
        self.assertFalse(probed["ok"])
        self.assertFalse(card["passes"])

    def test_a_clean_text_layer_with_eight_lemmas_passes(self) -> None:
        lines = ["1. Introduction", "This note records eight short lemmas about a finite group."]
        for number in range(1, 9):
            lines.append(f"Lemma 1.{number}. Let G be a finite group and let H be a subgroup.")
        card = classify_extraction(
            _extracted([_page(0, "\n".join(lines) + "\n")]),
            [{"number": "1", "title": "Introduction", "page": 1}],
        )
        self.assertEqual(card["failure_modes"], [])
        self.assertTrue(card["passes"])


if __name__ == "__main__":
    unittest.main()
