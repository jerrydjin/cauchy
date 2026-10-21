#!/usr/bin/env python3
"""Live semantic checks using Cauchy's grading instructions and authored data.

This calls the signed-in Codex CLI, incurs model usage, and sends only the
named evaluation fixture. It does not load learner workspaces or credentials.
Run explicitly; it is deliberately outside the offline unit test suite.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import textwrap


GRADES = {"correct", "partial", "incorrect", "uncertain"}


def effective_grade(assessment, rubric):
    """Match the app's proof gate, including decoding/text constraints."""
    def valid_text(value):
        return isinstance(value, str) and bool(value.strip()) and len(value) <= 6000

    if not isinstance(assessment, dict) or assessment.get("grade") not in GRADES:
        return "invalid_response"
    if not valid_text(assessment.get("feedback")) or not valid_text(assessment.get("nextStep")):
        return "invalid_response"
    criteria = assessment.get("criteria")
    if (not isinstance(rubric, list) or not 3 <= len(rubric) <= 8
            or not all(valid_text(item) for item in rubric) or not isinstance(criteria, list)):
        return "invalid_response"
    if len(criteria) != len(rubric) or any(not isinstance(c, dict) for c in criteria):
        return "invalid_response"
    indices = [c.get("index") for c in criteria]
    if any(type(i) is not int for i in indices) or set(indices) != set(range(len(rubric))):
        return "invalid_response"
    if any(c.get("outcome") not in {"met", "notMet", "uncertain"}
           or not valid_text(c.get("feedback")) for c in criteria):
        return "invalid_response"
    if any(c["outcome"] == "uncertain" for c in criteria):
        return "uncertain"
    if assessment["grade"] == "correct" and any(c["outcome"] == "notMet" for c in criteria):
        return "partial"
    return assessment["grade"]


def outcome_category(expected, grade):
    if grade == "uncertain":
        return "uncertainty"
    if grade in {"invalid_response", "invocation_error"}:
        return grade
    if grade in expected:
        return "matched"
    if grade == "correct" and "correct" not in expected:
        return "false_acceptance"
    if "correct" in expected and grade in {"partial", "incorrect"}:
        return "false_rejection"
    return "grade_mismatch"


def summarize(results):
    counts = {name: 0 for name in ("matched", "false_acceptance", "false_rejection", "uncertainty",
                                  "invalid_response", "invocation_error", "grade_mismatch")}
    for result in results:
        counts[result["outcomeCategory"]] += 1
    return dict(completedCases=len(results), expectedValid=sum("correct" in r["expectedGrades"] for r in results),
                expectedInvalid=sum("correct" not in r["expectedGrades"] for r in results), counts=counts,
                interpretation="Counts on authored engineering fixtures, not accuracy estimates or expert validation.")


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.with_suffix(path.suffix + ".tmp").write_text(json.dumps(report, indent=2) + "\n")
    path.with_suffix(path.suffix + ".tmp").replace(path)


def decode_object(raw):
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", raw):
        try:
            value, _ = decoder.raw_decode(raw[match.start():])
            if isinstance(value, dict) and "grade" in value:
                return value
        except json.JSONDecodeError:
            continue
    raise ValueError("No assessment object returned")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="Explicit currently supported model ID")
    parser.add_argument("--cases", default="docs/evaluation/proof-assessment-cases.json")
    parser.add_argument("--output", default="docs/evaluation/proof-assessment-expanded-results.json")
    parser.add_argument("--case", action="append", dest="selected", help="Run only a named case (repeatable)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    swift = (root / "Cauchy/Services/LearningTutorService.swift").read_text()
    match = re.search(r'private static let assessmentInstructions = """\n(.*?)\n    """', swift, re.S)
    if not match:
        raise ValueError("Cannot locate the app's current assessment instructions")
    instructions = textwrap.dedent(match.group(1)).strip()
    cases = json.loads((root / args.cases).read_text())
    if args.selected:
        unknown = set(args.selected) - {c["name"] for c in cases}
        if unknown:
            raise ValueError(f"Unknown cases: {sorted(unknown)}")
        cases = [c for c in cases if c["name"] in args.selected]
    if not cases or len({c["name"] for c in cases}) != len(cases):
        raise ValueError("Evaluation needs uniquely named authored cases")
    results = []
    report = dict(schemaVersion=2, model=args.model, evaluatedAt=datetime.now(timezone.utc).isoformat(),
                  dataScope="Authored synthetic cases only; no learner data or real notes",
                  reviewStatus="Engineering-authored reasoning; no independent external expert review",
                  instructionSHA256=hashlib.sha256(instructions.encode()).hexdigest(),
                  plannedCases=len(cases), complete=False, results=results, summary=summarize(results))
    output_path = root / args.output
    write_report(output_path, report)
    for case in cases:
        prompt = instructions + "\n\n" + json.dumps(case["input"]) + "\n" + (
            'Return only JSON: {"grade":"correct|partial|incorrect|uncertain",'
            '"feedback":"...","nextStep":"...","criteria":[{"index":0,'
            '"outcome":"met|notMet|uncertain","feedback":"specific evidence or gap"}]} '
            'Assess EVERY supplied criterion once using its zero-based index. Do not use tools.'
        )
        result = dict(name=case["name"], category=case.get("category", "legacy"), model=args.model,
                      expectedGrades=case["expectedGrades"], expectedReasoning=case.get("expectedReasoning"),
                      input=case["input"])
        try:
            run = subprocess.run([
            "codex", "exec", "-", "--json", "--skip-git-repo-check",
            "--sandbox", "read-only", "--model", args.model,
            "-c", 'model_reasoning_effort="medium"',
            ], input=prompt, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                cwd="/tmp", timeout=240)
            if run.returncode:
                raise RuntimeError(f"Model invocation exited {run.returncode}")
            messages = []
            for line in run.stdout.splitlines():
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                item = event.get("item", {})
                if event.get("type") == "item.completed" and item.get("type") == "agent_message":
                    messages.append(item.get("text", ""))
            try:
                assessment = decode_object("\n".join(messages))
                result["assessment"] = assessment
                grade = effective_grade(assessment, case["input"]["gradingCriteria"])
            except ValueError:
                grade = "invalid_response"
        except (subprocess.TimeoutExpired, RuntimeError, OSError) as error:
            grade = "invocation_error"
            # Never persist CLI stderr, which can contain local account details.
            result["errorType"] = type(error).__name__
        passed = grade in case["expectedGrades"]
        result.update(effectiveGrade=grade, matchedExpectation=passed,
                      outcomeCategory=outcome_category(case["expectedGrades"], grade))
        results.append(result)
        report["summary"] = summarize(results)
        write_report(output_path, report)
        print(f"{case['name']}: {grade} ({'matched' if passed else 'MISMATCH'})", flush=True)
    report["complete"] = True
    write_report(output_path, report)
    return 0 if all(r["matchedExpectation"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
