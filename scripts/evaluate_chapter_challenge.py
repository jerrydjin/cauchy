#!/usr/bin/env python3
"""Opt-in live check. Sends only authored metric-space fixtures to Codex.

Never opens a learner workspace or the user's PDF. Uses the app's exact current
chapter-generation and assessment instructions; saves auditable JSON results.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import textwrap
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parent.parent


def instruction(swift, name):
    match = re.search(r'private static let ' + name + r' = """\n(.*?)\n    """', swift, re.S)
    if not match:
        raise ValueError(f"Missing {name}")
    return textwrap.dedent(match.group(1)).strip()


def invoke(prompt, model):
    run = subprocess.run([
        "codex", "exec", "-", "--json", "--skip-git-repo-check", "--sandbox", "read-only",
        "--model", model, "-c", 'model_reasoning_effort="medium"',
    ], input=prompt + "\nDo not use tools. Return only the requested JSON.", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd="/tmp", timeout=240)
    if run.returncode:
        raise RuntimeError(f"Codex invocation failed (exit {run.returncode})")
    messages = []
    for line in run.stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = event.get("item", {})
        if event.get("type") == "item.completed" and item.get("type") == "agent_message":
            messages.append(item.get("text", ""))
    raw = "\n".join(messages)
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", raw):
        try:
            result, _ = decoder.raw_decode(raw[match.start():])
            if isinstance(result, dict):
                return result
        except json.JSONDecodeError:
            pass
    raise ValueError("No JSON object returned")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", default="docs/evaluation/chapter-challenge-results.json")
    args = parser.parse_args()
    swift = (ROOT / "Cauchy/Services/LearningTutorService.swift").read_text()
    fixture = json.loads((ROOT / "docs/evaluation/chapter-challenge-fixture.json").read_text())
    source = fixture["source"]
    generation = invoke(instruction(swift, "chapterInstructions") + "\n" + json.dumps(fixture)
                        + "\n" + instruction(swift, "chapterSchema"), args.model)
    output = {"provider": "codex", "evaluatedAt": datetime.now(timezone.utc).isoformat(), "model": args.model, "dataScope": "Authored synthetic fixture only; no learner data or real notes", "generation": generation, "assessments": []}
    path = ROOT / args.output
    path.write_text(json.dumps(output, indent=2) + "\n")
    print("Chapter generated; validating it in the app's local validator is a separate required check.", flush=True)
    question = fixture["authoredQuestion"]
    for name, answer, expected in [
        ("valid_modular_alternative", "K is a closed subset of the sequentially compact space X, so it is sequentially compact. The restriction of f to K is continuous. The continuous-image theorem therefore shows f(K) is sequentially compact. This includes the empty case, where the sequence condition is vacuous.", ["correct"]),
        ("circular_argument", "Since f(K) is sequentially compact, any sequence in f(K) has a convergent subsequence in f(K). Thus f(K) is sequentially compact.", ["partial", "incorrect"]),
        ("missing_closedness_step", "Take y_n in f(K) and preimages x_n in K. Since X is sequentially compact, a subsequence x_nk converges to a in X. Continuity gives y_nk converging to f(a), so f(K) is sequentially compact.", ["partial", "incorrect"]),
    ]:
        payload = dict(source=source["passages"][0]["text"], question=question["prompt"], kind="proof",
                       gradingCriteria=question["gradingCriteria"], expectedAnswer=question["expectedAnswer"], studentAnswer=answer)
        assessment = invoke(instruction(swift, "assessmentInstructions") + "\n" + json.dumps(payload)
                            + '\nReturn {"grade":"correct|partial|incorrect|uncertain","feedback":"...","nextStep":"...","criteria":[{"index":0,"outcome":"met|notMet|uncertain","feedback":"evidence or gap"}]}. Assess every supplied criterion once.', args.model)
        criteria = assessment.get("criteria", [])
        valid = len(criteria) == len(question["gradingCriteria"]) and {c.get("index") for c in criteria} == set(range(len(criteria)))
        grade = assessment.get("grade") if valid else "invalid_response"
        if any(c.get("outcome") == "uncertain" for c in criteria):
            grade = "uncertain"
        elif grade == "correct" and any(c.get("outcome") == "notMet" for c in criteria):
            grade = "partial"
        passed = grade in expected
        output["assessments"].append(dict(name=name, answer=answer, expectedGrades=expected, effectiveGrade=grade,
                                           matchedExpectation=passed, assessment=assessment))
        path.write_text(json.dumps(output, indent=2) + "\n")
        print(f"{name}: {grade} ({'matched' if passed else 'MISMATCH'})", flush=True)
    return 0 if all(item["matchedExpectation"] for item in output["assessments"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
