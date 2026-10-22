# Live proof evaluation fixture

Source: [linear-maps-source.txt](linear-maps-source.txt), authored for this project. It contains three definitions, two complete arguments, applications/counterexamples and an explicitly omitted rank-nullity proof. No private learner material is needed for this check.

Expected inventory: the zero-image property and kernel-subspace argument, injectivity and the trivial-kernel equivalence, their definitions and hypotheses, and rank-nullity with an open proof gap. Grouping may vary; no theorem may lose its proof obligation. Definitions and applications must not substitute for proof evidence.

Representative answer checks for the kernel-subspace proof:

| Answer | Required assessment behavior |
| --- | --- |
| “The kernel contains zero, so it is a subspace.” | Partial/incorrect; zero membership alone does not establish either closure property. Identify the first missing closure justification. |
| “I tried T(x,y)=x at three vectors and all the kernel vectors stay in the kernel.” | Partial/incorrect as a universal proof. A finite numerical example does not prove arbitrary closure or arbitrary T. |
| “The kernel is a subspace because linear maps have subspace kernels.” | Partial/incorrect; circular use of the claim being proved. |
| “Linearity gives T(0)=0. For u,v in the kernel and arbitrary real a,b, T(au+bv)=aT(u)+bT(v)=0. Hence the kernel contains zero and is closed under linear combinations, and therefore is a subspace.” | Correct if the equivalence with the supplied subspace conditions is accepted or justified. This alternative linear-combination argument must not be rejected for differing from the displayed proof. |
| “T(0)=0. For kernel vectors u,v, T(u+v)=T(u)+T(v)=0. For arbitrary a and kernel v, T(av)=aT(v)=0. This establishes all three subspace conditions.” | Correct, with all essential rubric criteria met. |
| “Every zero set of every map is a subspace.” | Incorrect; the supplied nonlinear counterexample disproves this. |

For Theorem 2, an answer proving only one implication must remain partial. For Theorem 3, no generated proof may be attributed to the supplied notes. Missing proof/context must remain open regardless of success on statement or application checks.

These are mathematically reviewed engineering fixtures, not a learner efficacy study or a substitute for external expert review. Record model, source, generated question/rubric, learner answer and assessment together when running them. Automated schema/gate tests check the implementation; live runs check the selected model's behavior on these examples.

## Observed live behavior

With GPT-6.1 Sol, the two-page fixture produced six study units with 18 requirements. Both complete theorem arguments received proof requirements. Rank-nullity kept its explicitly omitted proof open, along with prerequisites absent from the notes. Accounting for both pages did not count any requirement as learned.

The generated kernel-subspace lesson contained six explicit assumptions and 12 justified steps. Its diagnostic challenged an invalid use of scalar preservation for a nonlinear map. Its practice task required repairing circular zero membership and insufficient closure checks. The answer “The kernel contains zero, so it is a subspace” received an incorrect assessment and did not unlock the exit check. A revised, valid linear-combination argument was accepted, with all six practice criteria met.

The exit question changed structure to a fibre $U_b=\{v:T(v)=b\}$ and asked for the subspace equivalence with $b=0$, both implications, zero preservation and membership justifications without assuming the fibre is nonempty. This is a useful transfer check for this fixture, not evidence of a real learner's retention or of general model reliability. These authored engineering answers are not learner outcome data.

The first live exit assessment falsely penalized a valid proof for not restating givens and not adding a separate nonzero-fibre discussion already implied by the equivalence. The original record is retained. The grading instructions now explicitly accept problem givens, unambiguous standard identities and equivalent arguments, and audit generated rubrics for requirements beyond the question.

After that correction, a fresh run of all four [assessment cases](proof-assessment-cases.json) matched their expected outcomes: incomplete kernel proof incorrect, valid linear-combination proof correct, valid fibre-equivalence proof correct, and a missing reverse implication partial. [Results](proof-assessment-results.json) include the model and each criterion assessment. Re-run with `python3 scripts/evaluate_learning_proofs.py --model gpt-6.1-sol`; this invokes the signed-in CLI and consumes model usage. Four cases are an engineering check, not an accuracy estimate or a general validation of proof grading.

## Expanded evaluation — 17 October 2026

The authored case file now has **12 cases** with an explicit expected-reasoning note and category for every case. Added cases cover an alternative proof by additive cancellation, circular use of the theorem, numerical examples presented as a universal proof, a fixed scalar substituted for an arbitrary one, doubling one vector substituted for arbitrary addition, an absent linearity hypothesis, a valid counterexample detecting that absent hypothesis, and the empty-fibre case. These are engineering-authored mathematical checks; no independent external expert review has occurred.

The evaluator now writes a versioned report with the full input, expected reasoning, model identity, instruction hash and criterion-level response. Reports separately count false acceptance, false rejection, uncertainty, malformed responses, transport failures and other grade mismatches. It writes an incomplete checkpoint before invoking the model and saves after each case; an interrupted run cannot look complete. Counts on this small authored set must not be represented as general accuracy rates. The default new output is `proof-assessment-expanded-results.json`; the original four-case results are retained unchanged.

`python3 -m unittest discover -s scripts -p test_proof_evaluation.py -v` passes five offline checks, including replaying the four saved model assessments through the updated gate, malformed/duplicate criterion rejection, uncertainty handling and report accounting. These checks verify evaluator behavior, not model quality on the eight added cases.

After explicit user approval for these twelve synthetic cases, the live Codex/GPT-6.1 Sol run completed. [Expanded results](proof-assessment-expanded-results.json) retain all inputs and criterion-level responses: **4 expected-valid answers accepted, 8 expected-invalid answers rejected; 0 false acceptances, 0 false rejections, 0 uncertainty, 0 malformed responses, 0 invocation failures**. The first attempt was rejected by automatic approval review; it did not send a payload. No learner data or real notes were sent in the approved run.

`LearningRecordedProofTests` replays exact captured questions, answer keys, synthetic answers and assessments through the production learning state machine: a numerical-example diagnostic is rejected, the complete authored lesson leads to a valid alternative practice proof, and an independent fibre-equivalence exit proof succeeds after a saved-session restart. The replay refuses to attach a captured assessment to a different question, answer key, rubric, answer or source. It preserves criterion feedback, model identity and the exact requirement ID. The lesson is engineering-authored; this is an offline integration replay of live assessments, not a newly generated lesson or a native GUI observation. The existing live generated chapter fixture still passes the production source/criterion validator.

The 18 October follow-up complete macOS suite has 266 passing tests in `/tmp/cauchy-learning-completion-audit.xcresult`, with no failures or skips, plus five passing offline Python checks. The approved twelve-case live report is unchanged; no additional model calls were made for native verification. There is no independent external expert review, unseen-material benchmark or educational-efficacy result. Twelve cases and one replay are a reproducible quality gate with those limits, not general proof-grading validation.

## Recorded-evidence audit — 22 October 2026

[JERRY-94](https://linear.app/jerryjin/issue/JERRY-94) adds an offline command:

```bash
python3 scripts/audit_learning_proofs.py
python3 -m unittest discover -s scripts -p 'test_proof*.py' -v
```

The audit prints JSON and exits zero only when the retained report is internally consistent, complete for the current fixture, compatible with the current instruction/policy snapshot, and its recorded expectations matched. It reads the report, cases and grading instructions; it never invokes a model or rewrites those inputs. The auditor and live evaluator share the same instruction extractor. SHA-256 fields identify the report, fixture, current instructions and both Python implementations. Model IDs are checked for consistency within the recording.

The committed [audit output](proof-assessment-audit.json) finds a complete, internally consistent twelve-case report with exact current reference inputs, expected grades, reasoning notes and categories. All twelve recorded responses retain their outcomes under the current offline structural-policy replay. The original 17 October grading-instruction hash (`2bf4afb2…`) differs from the current hash (`9ccf3114…`). Accordingly **`checksPass` and `currentSnapshotCompatible` are false**, and the command exits **1**. The saved four-valid/eight-invalid results remain historical observations; current semantic behavior under the changed instructions remains unevaluated. Even a matching instruction hash would describe compatible saved inputs, without establishing present model behavior.

The audit separates declared-run completeness, whole-fixture coverage, changed references, internal grade/category/summary accounting, instruction drift and current policy replay. A consistent interrupted checkpoint remains visibly unfinished. A deliberately smaller completed run remains short of whole-fixture coverage. Duplicate/missing/unknown cases, changed questions/keys/answers/rubrics, inconsistent model IDs and corrupt accounting cannot pass. Current policy changes are shown beside recorded outcomes; uncertainty, malformed responses and invocation failures retain distinct counts. A missing raw assessment is marked unavailable for replay. The older four-case list format lacks the versioned lineage metadata and cannot pass this compatibility check; its existing offline replay remains available.

Inspection also reproduced two evaluator crashes: JSON arrays/dictionaries in the overall grade or criterion outcome raised `TypeError` during set membership. Those malformed values now return `invalid_response`, allowing the evaluator to retain its ordinary report/checkpoint behavior. This is evaluator robustness, with no change to app grading or to the historical captured responses.

All **15 offline Python tests pass**, including nine new audit tests covering drift, missing/duplicate/interrupted/subset records, malformed inputs, summary and model inconsistencies, policy changes, distinct uncertainty/error counts and a CLI call with model invocation/report writing replaced by failing mocks. The CLI and tests preserve the report/case bytes. Re-running the audit produces the same deterministic JSON. Both saved live result files and the authored cases remain unchanged. No new model call, learner-data access, external expert review or educational-efficacy result occurred. Swift/app inputs are unchanged from the 403-test export checkpoint, so that suite was not repeated for this Python/documentation-only milestone. The separate native export save/cancel verification subsequently completed; see the [saved-work export report](learning-work-export.md) for its observed scope and limits.
