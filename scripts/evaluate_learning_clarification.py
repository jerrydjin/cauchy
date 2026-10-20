#!/usr/bin/env python3
"""Opt-in live prompt check using authored source only, never learner notes.

Uses production clarification instructions/schema. Structural checks locate
quotes and check declared basis; they do not certify mathematical correctness.
The app's Swift validator and a review of actual answers are separate checks.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from evaluate_chapter_challenge import instruction, invoke

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--feedback", action="store_true", help="Check saved-assessment explanations instead of teaching steps")
    parser.add_argument("--output", help="Result JSON path (defaults to a separate file for each check suite)")
    args = parser.parse_args()
    swift = (ROOT / "Cauchy/Services/LearningTutorService.swift").read_text()
    cases = [
        dict(name="closedness_keeps_limit", source="A metric space X is sequentially compact if every sequence in X has a subsequence converging to a point of X. A closed subset K of X contains the limits in X of its convergent sequences. Proof of the closed-subset theorem: take a sequence in K, select a subsequence converging in X, then use closedness to place its limit in K.",
             teaching="A closed subset of a sequentially compact metric space is sequentially compact. Choose a subsequence converging in X; closedness puts the limit in K.",
             question="Why exactly is closedness needed in this step?", expectedBasis=["suppliedNotes"]),
        dict(name="omitted_proof", source="Theorem: the continuous image of a compact topological space is compact. The proof is omitted from these notes. No definition of compactness or supporting lemmas is supplied on this page.",
             teaching="The continuous image theorem is stated, but the source argument is unavailable.",
             question="Can you walk me through the proof from these notes? Do not supply an outside proof.", expectedBasis=["insufficientSource"]),
        dict(name="challenge_faulty_teaching", source="A map T between real vector spaces is linear when T(u+v)=T(u)+T(v) and T(cu)=cT(u) for all vectors u,v and real scalars c. In particular T(0)=0. The map f:R->R defined by f(x)=x*x is continuous but is not linear: f(2)=4 whereas 2*f(1)=2.",
             teaching="Every continuous function is linear because preserving limits means preserving sums and scalar multiples.",
             question="Is the claim in this generated teaching step actually correct?", expectedBasis=["suppliedNotes"]),
    ]
    if args.feedback:
        cases = [
            dict(name="challenge_faulty_assessment", source="A map T between real vector spaces is linear when T(u+v)=T(u)+T(v) and T(cu)=cT(u) for all vectors u,v and real scalars c. In particular T(0)=T(0+0)=T(0)+T(0). Subtracting T(0) from both sides gives T(0)=0. Injectivity is not required.",
                 teaching="Assessed question: Prove that a linear map sends zero to zero.\nLearner answer: T(0)=T(0+0)=T(0)+T(0). Subtract T(0) from both sides to obtain T(0)=0.\nTutor assessment: Needs another look\nThis proof fails because T must be injective.\nSuggested next step: Add injectivity as a hypothesis.\nCriterion 1: Justify zero preservation.\nnotMet: Injectivity is missing.",
                 question="Why does this feedback require injectivity? Is that actually needed?", expectedBasis=["suppliedNotes"],
                 reviewExpectation="Recognize that the submitted cancellation proof is valid and the feedback's injectivity demand is wrong, without claiming to change the stored grade."),
            dict(name="explain_missing_closedness", source="A metric space X is sequentially compact if every sequence in X has a subsequence converging to a point of X. A closed subset K of X contains the limits in X of its convergent sequences. A continuous map sends a convergent sequence to a sequence converging to the image of its limit.",
                 teaching="Assessed question: If K is a closed subset of sequentially compact X and f is continuous, prove f(K) is sequentially compact.\nLearner answer: Choose preimages x_n in K of a sequence in f(K). Sequential compactness of X gives x_nk converging to a in X. Continuity gives f(x_nk) converging to f(a). Thus f(K) is sequentially compact.\nTutor assessment: Partly correct\nYou have not justified that f(a) belongs to f(K).\nSuggested next step: Locate the limit using closedness.\nCriterion 1: Justify the limit location.\nnotMet: Membership of a in K is missing.",
                 question="I already have convergence. What is still missing in my answer?", expectedBasis=["suppliedNotes"],
                 reviewExpectation="Distinguish convergence in the ambient space from a limit in f(K); explain the use of closedness to place a in K."),
        ]
    output = dict(model=args.model, evaluatedAt=datetime.now(timezone.utc).isoformat(),
                  dataScope="Authored synthetic source only; no learner data or real notes", results=[])
    path = ROOT / (args.output or ("docs/evaluation/learning-feedback-results.json" if args.feedback
                                  else "docs/evaluation/learning-clarification-results.json"))
    for case in cases:
        payload = dict(source="PDF page 1:\n" + case["source"],
                       context=dict(phase="lesson", partIndex=0, title="Current idea", content=case["teaching"]),
                       question=case["question"], previous=[])
        if args.feedback:
            payload["context"].update(phase="exitCheck", partIndex=None, title="Tutor feedback",
                                      attemptID="70000000-0000-4000-8000-000000000080")
        reply = invoke(instruction(swift, "clarificationInstructions") + "\n" + json.dumps(payload)
                       + "\n" + instruction(swift, "clarificationSchema"), args.model)
        citations = reply.get("citations", [])
        normalized = lambda value: " ".join(value.split())
        valid = (isinstance(reply.get("answer"), str) and 0 < len(reply["answer"]) <= 6000
                 and len(citations) <= 6
                 and all(c.get("pageIndex") == 0 and len(normalized(c.get("quote", ""))) >= 24
                         and normalized(c["quote"]) in normalized(case["source"]) for c in citations)
                 and (reply.get("basis") != "suppliedNotes" or bool(citations)))
        output["results"].append(dict(case, reply=reply, structuralCheck=valid,
                                      declaredBasisMatched=reply.get("basis") in case["expectedBasis"]))
        path.write_text(json.dumps(output, indent=2) + "\n")
        print(f'{case["name"]}: structure={valid}, declared basis={reply.get("basis")}', flush=True)
    return 0 if all(item["structuralCheck"] and item["declaredBasisMatched"] for item in output["results"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
