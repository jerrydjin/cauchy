"""Offline report-lineage checks; never send a fixture to a model."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from audit_learning_proofs import assessment_instructions, audit_report, main
from evaluate_learning_proofs import summarize


class ProofAuditTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parent.parent
        self.report_path = self.root / "docs/evaluation/proof-assessment-expanded-results.json"
        self.cases_path = self.root / "docs/evaluation/proof-assessment-cases.json"
        self.report = json.loads(self.report_path.read_text())
        self.cases = json.loads(self.cases_path.read_text())
        self.instructions = assessment_instructions(self.root)

    def compatible_metadata(self):
        # Synthetic metadata mutation for validator tests, not a new model run.
        report = copy.deepcopy(self.report)
        report["instructionSHA256"] = hashlib.sha256(self.instructions.encode()).hexdigest()
        return report

    def audit(self, report, cases=None, instructions=None):
        return audit_report(report, self.cases if cases is None else cases,
                            self.instructions if instructions is None else instructions)

    def test_saved_evidence_is_replayed_without_claiming_new_model_results(self):
        report = copy.deepcopy(self.report)
        cases = copy.deepcopy(self.cases)
        result = self.audit(report, cases)
        self.assertTrue(result["integrityValid"])
        self.assertTrue(result["declaredRunComplete"])
        self.assertTrue(result["coverage"]["complete"])
        self.assertEqual(result["referenceMismatches"], [])
        self.assertEqual(result["currentPolicyReplay"]["changes"], [])
        self.assertEqual(result["currentPolicyReplay"]["summary"]["counts"]["matched"], 12)
        self.assertEqual(result["instructionsMatch"], self.report["instructionSHA256"] == result["currentInstructionSHA256"])
        self.assertEqual(report, self.report)
        self.assertEqual(cases, self.cases)
        self.assertIn("No new model evaluation", result["interpretation"])

    def test_instruction_drift_blocks_current_snapshot_compatibility(self):
        report = self.compatible_metadata()
        self.assertTrue(self.audit(report)["checksPass"])
        changed = self.audit(report, instructions=self.instructions + "\nDifferent grading policy.")
        self.assertTrue(changed["integrityValid"])
        self.assertFalse(changed["instructionsMatch"])
        self.assertFalse(changed["currentSnapshotCompatible"])
        self.assertFalse(changed["checksPass"])
        self.assertEqual(changed["recomputedRecordedSummary"]["counts"]["matched"], 12)

    def test_changed_source_question_answer_rubric_or_expected_reference_is_explicit(self):
        for field in ("source", "question", "expectedAnswer", "studentAnswer", "gradingCriteria"):
            report = self.compatible_metadata()
            value = report["results"][0]["input"]
            if field == "gradingCriteria":
                value[field][0] += " Changed criterion."
            else:
                value[field] += " Changed reference."
            with self.subTest(field=field):
                result = self.audit(report)
                self.assertFalse(result["checksPass"])
                self.assertIn("input", result["referenceMismatches"][0]["fields"])
        for field, value in [("expectedGrades", ["correct"]), ("expectedReasoning", "A revised reasoning reference."),
                             ("category", "reclassified")]:
            report = self.compatible_metadata(); report["results"][0][field] = value
            result = self.audit(report)
            self.assertIn(field, result["referenceMismatches"][0]["fields"])
            self.assertFalse(result["checksPass"])

    def test_duplicate_missing_unknown_and_interrupted_cases_cannot_pass(self):
        report = self.compatible_metadata()
        report["results"][1] = copy.deepcopy(report["results"][0])
        duplicate = self.audit(report)
        self.assertIn("duplicate_result", {e["code"] for e in duplicate["integrityErrors"]})
        self.assertFalse(duplicate["coverage"]["complete"])
        report = self.compatible_metadata()
        report["results"] = report["results"][:3]
        report["complete"] = False
        report["summary"] = summarize(report["results"])
        partial = self.audit(report)
        self.assertTrue(partial["integrityValid"])  # A checkpoint can be internally consistent and unfinished.
        self.assertFalse(partial["declaredRunComplete"])
        self.assertEqual(len(partial["coverage"]["missing"]), 9)
        self.assertFalse(partial["checksPass"])
        report["complete"] = True
        self.assertIn("completion_count_mismatch", {e["code"] for e in self.audit(report)["integrityErrors"]})
        report["plannedCases"] = 3
        subset = self.audit(report)
        self.assertTrue(subset["declaredRunComplete"])
        self.assertFalse(subset["coverage"]["complete"])
        report = self.compatible_metadata(); report["results"][0]["name"] = "removed_fixture_case"
        unknown = self.audit(report)
        self.assertIn("removed_fixture_case", unknown["coverage"]["unknown"])
        self.assertFalse(unknown["checksPass"])

    def test_inconsistent_model_accounting_and_summary_are_rejected(self):
        mutations = [lambda r: r["results"][0].__setitem__("model", "another-model"),
                     lambda r: r["results"][0].__setitem__("outcomeCategory", "false_acceptance"),
                     lambda r: r["results"][0].__setitem__("matchedExpectation", False),
                     lambda r: r["summary"]["counts"].__setitem__("matched", 99),
                     lambda r: r["summary"]["counts"].__setitem__("false_acceptance", False),
                     lambda r: r.__setitem__("complete", "true"),
                     lambda r: r.__setitem__("instructionSHA256", "unverifiable"),
                     lambda r: r.__setitem__("evaluatedAt", "2026-10-17"),
                     lambda r: r.__setitem__("plannedCases", True)]
        for mutation in mutations:
            report = self.compatible_metadata(); mutation(report)
            result = self.audit(report)
            self.assertFalse(result["integrityValid"])
            self.assertFalse(result["checksPass"])

    def test_policy_replay_changes_do_not_rewrite_the_recorded_counts(self):
        report = self.compatible_metadata()
        result = next(r for r in report["results"] if r["effectiveGrade"] == "correct")
        result["assessment"]["criteria"][0]["outcome"] = "notMet"
        audited = self.audit(report)
        self.assertEqual(audited["recomputedRecordedSummary"]["counts"]["matched"], 12)
        self.assertEqual(audited["currentPolicyReplay"]["summary"]["counts"]["false_rejection"], 1)
        self.assertEqual(audited["currentPolicyReplay"]["changes"][0]["currentPolicyGrade"], "partial")
        self.assertFalse(audited["currentSnapshotCompatible"])

    def test_uncertainty_malformed_responses_and_transport_errors_stay_distinct(self):
        for grade, assessment in [("uncertain", "uncertain"), ("invalid_response", "invalid"), ("invocation_error", None)]:
            report = self.compatible_metadata()
            result = report["results"][0]
            result.update(effectiveGrade=grade, matchedExpectation=False,
                          outcomeCategory="uncertainty" if grade == "uncertain" else grade)
            if assessment is None:
                result.pop("assessment")
            elif assessment == "uncertain":
                result["assessment"]["criteria"][0]["outcome"] = "uncertain"
            else:
                result["assessment"]["grade"] = []
            report["summary"] = summarize(report["results"])
            audited = self.audit(report)
            self.assertTrue(audited["integrityValid"])
            counts = audited["currentPolicyReplay"]["summary"]["counts"]
            self.assertEqual(counts[result["outcomeCategory"]], 1)
            self.assertEqual(counts["false_acceptance"], 0)
            self.assertEqual(counts["false_rejection"], 0)
            self.assertFalse(audited["checksPass"])

    def test_malformed_input_and_legacy_reports_fail_without_crashing(self):
        for report in [None, [], self.report["results"], {}, dict(self.report, results=[None]),
                       dict(self.report, results="not a list")]:
            self.assertFalse(self.audit(report)["checksPass"])
        cases = copy.deepcopy(self.cases); cases.append(cases[0])
        self.assertIn("duplicate_fixture_case", {e["code"] for e in self.audit(self.report, cases)["integrityErrors"]})
        report = self.compatible_metadata(); report["results"][0]["effectiveGrade"] = {}
        self.assertFalse(self.audit(report)["checksPass"])

    def test_cli_is_read_only_and_never_invokes_the_live_evaluator(self):
        report_before = self.report_path.read_bytes(); cases_before = self.cases_path.read_bytes()
        with patch("evaluate_learning_proofs.subprocess.run", side_effect=AssertionError("No model invocation")), \
             patch("evaluate_learning_proofs.write_report", side_effect=AssertionError("No report rewrite")), \
             contextlib.redirect_stdout(io.StringIO()) as captured:
            status = main([])
        result = json.loads(captured.getvalue())
        self.assertEqual(status, 0 if result["checksPass"] else 1)
        self.assertEqual(result["reportSHA256"], hashlib.sha256(report_before).hexdigest())
        self.assertEqual(result["fixtureSHA256"], hashlib.sha256(cases_before).hexdigest())
        self.assertEqual(result["auditorImplementationSHA256"], hashlib.sha256((self.root / "scripts/audit_learning_proofs.py").read_bytes()).hexdigest())
        self.assertEqual(self.report_path.read_bytes(), report_before)
        self.assertEqual(self.cases_path.read_bytes(), cases_before)
        with tempfile.TemporaryDirectory() as directory:
            bad = Path(directory) / "malformed.json"; bad.write_text("not json")
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                self.assertEqual(main(["--report", str(bad)]), 1)
            self.assertEqual(json.loads(captured.getvalue())["integrityErrors"][0]["code"], "unreadable_audit_input")


if __name__ == "__main__":
    unittest.main()
