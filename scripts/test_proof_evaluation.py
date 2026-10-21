"""Offline checks for proof-evaluation accounting; no model or learner data."""
import copy
import json
from pathlib import Path
import unittest

from evaluate_learning_proofs import effective_grade, outcome_category, summarize


class ProofEvaluationTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parent.parent
        self.cases = json.loads((root / "docs/evaluation/proof-assessment-cases.json").read_text())
        self.previous = json.loads((root / "docs/evaluation/proof-assessment-results.json").read_text())

    def test_saved_live_assessments_retain_their_effective_grades(self):
        # Apply the new gate to previously captured real responses, rather
        # than claiming new model results from synthetic fake assessments.
        cases = {case["name"]: case for case in self.cases}
        for result in self.previous:
            with self.subTest(case=result["name"]):
                self.assertEqual(effective_grade(result["assessment"], cases[result["name"]]["input"]["gradingCriteria"]),
                                 result["effectiveGrade"])

    def test_uncertainty_and_rejected_responses_never_become_acceptance_or_rejection(self):
        responses = [("correct", "correct"), ("partial", "false_rejection"),
                     ("uncertain", "uncertainty"), ("invalid_response", "invalid_response"),
                     ("invocation_error", "invocation_error")]
        for grade, expected in responses:
            expected_category = "matched" if expected == "correct" else expected
            self.assertEqual(outcome_category(["correct"], grade), expected_category)
        self.assertEqual(outcome_category(["partial", "incorrect"], "correct"), "false_acceptance")
        results = [dict(expectedGrades=["correct"], outcomeCategory=outcome_category(["correct"], g)) for g, _ in responses]
        counts = summarize(results)["counts"]
        self.assertEqual(counts["false_acceptance"], 0)
        self.assertEqual(counts["false_rejection"], 1)
        self.assertEqual(counts["uncertainty"], 1)
        self.assertEqual(counts["invocation_error"], 1)

    def test_duplicate_unknown_and_missing_criteria_cannot_pass(self):
        result = next(r for r in self.previous if r["effectiveGrade"] == "correct")
        rubric = next(c for c in self.cases if c["name"] == result["name"])["input"]["gradingCriteria"]
        for mutation in [lambda a: a["criteria"].pop(),
                         lambda a: a["criteria"].__setitem__(0, a["criteria"][1]),
                         lambda a: a["criteria"][0].__setitem__("index", True),
                         lambda a: a["criteria"][0].__setitem__("outcome", "guessed"),
                         lambda a: a.__setitem__("grade", "mastered"),
                         lambda a: a.__setitem__("feedback", ""),
                         lambda a: a.__setitem__("nextStep", "x" * 6001)]:
            assessment = copy.deepcopy(result["assessment"])
            mutation(assessment)
            self.assertEqual(effective_grade(assessment, rubric), "invalid_response")

    def test_not_met_and_uncertain_criteria_override_optimistic_grade(self):
        result = next(r for r in self.previous if r["effectiveGrade"] == "correct")
        rubric = next(c for c in self.cases if c["name"] == result["name"])["input"]["gradingCriteria"]
        assessment = copy.deepcopy(result["assessment"])
        assessment["criteria"][0]["outcome"] = "notMet"
        self.assertEqual(effective_grade(assessment, rubric), "partial")
        assessment["criteria"][1]["outcome"] = "uncertain"
        self.assertEqual(effective_grade(assessment, rubric), "uncertain")

    def test_unusable_rubric_text_cannot_earn_a_correct_result(self):
        result = next(r for r in self.previous if r["effectiveGrade"] == "correct")
        rubric = next(c for c in self.cases if c["name"] == result["name"])["input"]["gradingCriteria"]
        for text in ["", " ", "x" * 6001, None]:
            invalid = list(rubric)
            invalid[0] = text
            self.assertEqual(effective_grade(result["assessment"], invalid), "invalid_response")

    def test_fixture_has_explicit_reasons_for_each_required_failure_class(self):
        categories = {c["category"] for c in self.cases}
        self.assertTrue({"valid_alternative", "missing_hypothesis", "circular_reasoning", "quantifier_error",
                         "missing_cases", "examples_as_proof"}.issubset(categories))
        self.assertEqual(len({c["name"] for c in self.cases}), len(self.cases))
        for case in self.cases:
            self.assertTrue(case["expectedReasoning"].strip())
            self.assertTrue(3 <= len(case["input"]["gradingCriteria"]) <= 8)


if __name__ == "__main__":
    unittest.main()
