# Consistent saved study-session outcomes

Tracked by [JERRY-130](https://linear.app/jerryjin/issue/JERRY-130), following [read-only session history](learning-study-session-history.md) and [assessment consistency](learning-assessment-consistency.md).

## Problem and behavior

Session records displayed **correct without help** whenever their cached `Outcome.independentCorrect` flag was true. Unlike lesson progress, they did not recheck the linked assessment's criteria. An optimistic legacy outcome could therefore describe success even when its original saved assessment was structurally inconsistent and could not earn evidence.

Each item now resolves its exact recorded session and attempt, then checks requirement identity, ordinary/delayed activity, the saved-lesson/item binding, exit phase and question kind. Attempts listed as already present when the plan began cannot be presented as new work in that session. Missing references and mismatches have distinct explanations beside the original recorded grade. No latest or unrelated attempt can fill a missing reference. Valid older requirement versions remain readable without consulting the current course.

A set-aside assessment retains its exclusion label. Otherwise the read-only resolver applies the shared `LearningAssessmentPolicy`, rejects a contradictory grade, checks grade/help agreement with the snapshot and prevents an unsupported independent-correct flag from being displayed as success. It does not infer mathematical correctness from structural agreement. The internal verified status means consistent saved metadata and assessment structure only.

The existing renderer is shared by the current finished-session card and past-session history. Inconsistent records say **recorded grade: Correct · assessment needs checking**. Missing and mismatched records retain their recorded grade with an explanation. Valid helped work and unfinished requirements keep their existing labels. This changes presentation only: original grades, criteria, answers, outcomes, dates, assistance and exclusions are never rewritten, and the existing evidence/progress policy is unchanged. Reinstatement does not promote a snapshot that was originally captured as excluded.

## Automated verification — 26 October 2026

All **452 normal macOS tests pass**, with zero failures/skips and no reported runtime warnings. Three new regressions and an updated exclusion assertion establish:

* Concept, proof and application outcomes with incomplete, unmet or uncertain criteria cannot rely on an optimistic cached flag. Grade/help disagreement and impossible assisted-success flags are qualified while raw assessments and snapshots remain unchanged.
* Exact session/attempt references, unit/kind/objective/revision, ordinary/delayed mode, saved-lesson/item binding, chapter exclusion and exit phase are required. Pre-plan attempts and unattached same-goal results cannot be borrowed. Missing, unrelated, unbound and changed records remain qualified; course-context-only reorganization stays usable. Empty outcomes stay unfinished.
* Set-aside and reinstated assessments are reflected without rewriting captured flags. Real persistence round-trip and read-only lookup work without a composed course, retaining the original outcome and complete learning-file bytes.

The isolated archive `/tmp/cauchy-record130-validation` starts at `cf28d57` and overlays four exact implementation/test files recorded in `/tmp/cauchy-record130-inputs.json`. The initial complete suite passed before additional association/pre-plan assertions. The authoritative final results are `/tmp/cauchy-record130-final.xcresult`, `/tmp/cauchy-record130-final.log` and `/tmp/cauchy-record130-final-summary.json`; all 452 tests pass. The standard unoptimized Debug host uses `/Applications/Xcode.app`, pinned SwiftMath `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` and the existing resolved package cache with automatic resolution disabled. No new ordinary Swift file requires project regeneration.

## Native verification

The exact tested runtime `/tmp/cauchy-record130-final-tested.dylib` (SHA-256 `807b2025fca7fe3e21d0f370b3975604f89defc8e2f41f64c6d94a43cde31c67`) was observed in the stopped-then-prepared disposable app against `/tmp/cauchy-ui-fixture-record130-native`. No wrapper or assistant-setting change was used.

The authored history includes three optimistic legacy records: a correct grade with an unmet essential criterion, a missing linked assessment and a mismatched requirement. Each retained its original cached success flag and recorded grade. The native sheet qualified each as **assessment needs checking**, **saved assessment unavailable** or **saved assessment does not match this record**; none showed **correct without help**. An earlier native pass, before the final association guards, visually inspected the contradiction's rendered explanation and retained the set-aside label, supported-work label and unfinished requirement. The display source did not change when those guards were added. The final exact build rechecked all three integrity explanations before and after cold restart.

Closing history returned to the unchanged paused-plan path. After a confirmed quit, all four complete parsed learning records matched `/tmp/cauchy-record130-native-before.json`. A cold restart restored the same path; reopening history reproduced all three integrity explanations. A second complete comparison at final quit again matched the original records, including grades, criteria, answers, cached outcomes, recency, maps and drafts. No answer was edited or assessed and no plan was advanced or finished.

Final cleanup asserted process absence inside the restoration command, then restored the temporary app's original plist and dylib byte-for-byte from `/tmp/cauchy-record130-original.info.plist` and `/tmp/cauchy-record130-original.dylib`. The installed app, normal learner library, reader and system settings remain unchanged.

These checks establish reference/record consistency and the stated native labels, not mathematical grading accuracy, whole-course learning or retention. Exhaustive corruption recovery and comprehensive accessibility remain unproven. No live model evaluation, push, merge or release occurred.
