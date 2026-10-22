#!/usr/bin/env python3
"""Audit recorded proof assessments offline; never invoke a model or rewrite inputs.

Exit 0 means the saved report is consistent with this fixture/instruction
snapshot and its recorded expectations. It is not a new semantic evaluation.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

from evaluate_learning_proofs import GRADES, assessment_instructions, effective_grade, outcome_category, summarize


def audit_report(report, cases, instructions):
    errors = []
    mismatches = []
    replay_changes = []
    unavailable = []
    recorded_rows = []
    replay_rows = []
    names = []
    current_hash = hashlib.sha256(instructions.encode()).hexdigest()

    def error(code, location):
        errors.append(dict(code=code, location=location))

    def valid_grades(value):
        return (isinstance(value, list) and bool(value)
                and all(isinstance(g, str) and g in GRADES for g in value)
                and len(set(value)) == len(value))

    def valid_input(value):
        return (isinstance(value, dict) and value.get("kind") == "proof"
                and all(isinstance(value.get(k), str) for k in ("source", "question", "expectedAnswer", "studentAnswer"))
                and isinstance(value.get("gradingCriteria"), list)
                and 3 <= len(value["gradingCriteria"]) <= 8
                and all(isinstance(c, str) and c.strip() and len(c) <= 6000 for c in value["gradingCriteria"]))

    references = {}
    if not isinstance(cases, list) or not cases:
        error("invalid_fixture", "cases")
    else:
        for index, case in enumerate(cases):
            location = f"cases[{index}]"
            if (not isinstance(case, dict) or not isinstance(case.get("name"), str) or not case["name"].strip()
                    or not valid_input(case.get("input")) or not valid_grades(case.get("expectedGrades"))
                    or not all(isinstance(case.get(k), str) and case[k].strip() for k in ("category", "expectedReasoning"))):
                error("invalid_fixture_case", location)
                continue
            if case["name"] in references:
                error("duplicate_fixture_case", case["name"])
            references[case["name"]] = case

    if not isinstance(report, dict):
        error("unsupported_report_format", "report")
        report = {}
    if type(report.get("schemaVersion")) is not int or report["schemaVersion"] != 2:
        error("unsupported_report_schema", "schemaVersion")
    model = report.get("model")
    if not isinstance(model, str) or not model.strip():
        error("missing_model", "model")
    recorded_hash = report.get("instructionSHA256")
    if not isinstance(recorded_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", recorded_hash):
        error("invalid_instruction_hash", "instructionSHA256")
    try:
        evaluated = report.get("evaluatedAt")
        if not isinstance(evaluated, str) or datetime.fromisoformat(evaluated.replace("Z", "+00:00")).utcoffset() is None:
            raise ValueError()
    except ValueError:
        error("invalid_evaluation_date", "evaluatedAt")
    planned = report.get("plannedCases")
    if type(planned) is not int or planned < 1:
        error("invalid_planned_count", "plannedCases")
    if type(report.get("complete")) is not bool:
        error("missing_completion_state", "complete")
    results = report.get("results")
    if not isinstance(results, list):
        error("invalid_results", "results")
        results = []
    for index, result in enumerate(results):
        location = f"results[{index}]"
        if not isinstance(result, dict) or not isinstance(result.get("name"), str) or not result["name"].strip():
            error("invalid_result", location)
            continue
        name = result["name"]
        if name in names:
            error("duplicate_result", name)
        names.append(name)
        if result.get("model") != model:
            error("model_mismatch", name)
        reference = references.get(name)
        fields = [k for k in ("input", "expectedGrades", "expectedReasoning", "category")
                  if reference is not None and result.get(k) != reference.get(k)]
        if reference is None:
            fields = ["case_missing_from_current_fixture"]
        if fields:
            mismatches.append(dict(name=name, fields=fields))
        expected = result.get("expectedGrades")
        grade = result.get("effectiveGrade")
        if not valid_input(result.get("input")) or not valid_grades(expected):
            error("invalid_recorded_input", name)
            continue
        if not isinstance(grade, str) or grade not in GRADES | {"invalid_response", "invocation_error"}:
            error("invalid_recorded_grade", name)
            continue
        category = outcome_category(expected, grade)
        if result.get("outcomeCategory") != category:
            error("outcome_accounting_mismatch", name)
        if type(result.get("matchedExpectation")) is not bool or result["matchedExpectation"] != (grade in expected):
            error("expectation_accounting_mismatch", name)
        recorded_rows.append(dict(expectedGrades=expected, outcomeCategory=category))
        if "assessment" in result:
            if grade == "invocation_error":
                error("invocation_error_has_assessment", name)
            replayed = effective_grade(result["assessment"], result["input"]["gradingCriteria"])
        else:
            unavailable.append(name)
            if grade not in {"invocation_error", "invalid_response"}:
                error("missing_assessment", name)
            replayed = grade
        replay_rows.append(dict(expectedGrades=expected, outcomeCategory=outcome_category(expected, replayed)))
        if replayed != grade:
            replay_changes.append(dict(name=name, recordedGrade=grade, currentPolicyGrade=replayed))

    recorded_summary = summarize(recorded_rows)
    supplied_summary = report.get("summary")
    summary_valid = isinstance(supplied_summary, dict)
    for key in ("completedCases", "expectedValid", "expectedInvalid"):
        summary_valid = (summary_valid and type(supplied_summary.get(key)) is int
                         and supplied_summary[key] == recorded_summary[key])
    counts = supplied_summary.get("counts") if isinstance(supplied_summary, dict) else None
    summary_valid = (summary_valid and isinstance(counts, dict)
                     and all(type(n) is int for n in counts.values()) and counts == recorded_summary["counts"])
    if not summary_valid:
        error("summary_accounting_mismatch", "summary")
    if type(planned) is int and (len(results) > planned or report.get("complete") is True and len(results) != planned):
        error("completion_count_mismatch", "plannedCases/results")
    run_complete = report.get("complete") is True and type(planned) is int and len(results) == planned and len(set(names)) == planned
    missing = sorted(set(references) - set(names))
    unknown = sorted(set(names) - set(references))
    coverage_complete = bool(references) and not missing and not unknown and len(names) == len(references)
    instructions_match = recorded_hash == current_hash
    compatible = (not errors and run_complete and coverage_complete and not mismatches
                  and instructions_match and not replay_changes and not unavailable)
    expectations_matched = (bool(recorded_rows) and len(recorded_rows) == len(results)
                            and all(row["outcomeCategory"] == "matched" for row in recorded_rows))
    return dict(
        auditSchemaVersion=1, recordedModel=model, recordedEvaluationAt=report.get("evaluatedAt"),
        recordedInstructionSHA256=recorded_hash, currentInstructionSHA256=current_hash,
        instructionsMatch=instructions_match, integrityValid=not errors, integrityErrors=errors,
        declaredRunComplete=run_complete,
        coverage=dict(currentFixtureCases=len(references), recordedUniqueCases=len(set(names)),
                      complete=coverage_complete, missing=missing, unknown=unknown),
        referenceMismatches=mismatches, recomputedRecordedSummary=recorded_summary,
        currentPolicyReplay=dict(summary=summarize(replay_rows), changes=replay_changes, unavailableCases=unavailable),
        currentSnapshotCompatible=compatible, recordedExpectationsMatched=expectations_matched,
        checksPass=compatible and expectations_matched,
        interpretation="Offline integrity/accounting and structural-policy replay of historical responses. "
                       "No new model evaluation, mathematical verification, expert review or efficacy evidence. "
                       "A matching instruction hash does not establish current model behavior.",
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="docs/evaluation/proof-assessment-expanded-results.json")
    parser.add_argument("--cases", default="docs/evaluation/proof-assessment-cases.json")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    try:
        report_bytes = (root / args.report).read_bytes()
        case_bytes = (root / args.cases).read_bytes()
        result = audit_report(json.loads(report_bytes), json.loads(case_bytes), assessment_instructions(root))
        result["reportSHA256"] = hashlib.sha256(report_bytes).hexdigest()
        result["fixtureSHA256"] = hashlib.sha256(case_bytes).hexdigest()
        result["auditorImplementationSHA256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        result["evaluatorImplementationSHA256"] = hashlib.sha256((root / "scripts/evaluate_learning_proofs.py").read_bytes()).hexdigest()
    except (OSError, UnicodeError, ValueError) as error:
        result = dict(auditSchemaVersion=1, checksPass=False, integrityValid=False,
                      integrityErrors=[dict(code="unreadable_audit_input", errorType=type(error).__name__)])
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["checksPass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
