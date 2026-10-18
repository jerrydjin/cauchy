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
    parser.add_argument("--output", default="docs/evaluation/learning-clarification-results.json")
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
    output = dict(model=args.model, evaluatedAt=datetime.now(timezone.utc).isoformat(),
                  dataScope="Authored synthetic source only; no learner data or real notes", results=[])
    path = ROOT / args.output
    for case in cases:
        payload = dict(source="PDF page 1:\n" + case["source"],
                       context=dict(phase="lesson", partIndex=0, title="Current idea", content=case["teaching"]),
                       question=case["question"], previous=[])
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
