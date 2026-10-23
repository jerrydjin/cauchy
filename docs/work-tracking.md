# Work tracking

The [Cauchy Linear project](https://linear.app/jerryjin/project/cauchy-a3df35a6c1f5) records priorities, scope, dependencies and remaining acceptance criteria. The codebase is the source of truth for implemented behavior. Tests and repository evaluation reports establish what was checked and what remains uncertain.

Before starting an issue, inspect the current implementation and existing work. Before updating its status, compare the acceptance criteria with code and actual verification. A successful build is not native UI verification; an agent's completion message is not a substitute for evidence. Keep source accounting, independent learning evidence and retention claims separate.

Keep detailed implementation decisions and evaluation evidence in the repository. Linear should remain a concise work register, without copies of source notes, learner answers or private repository details. Do not maintain a second status backlog here. Add a commit or PR reference when one actually exists. Local checkpoints must not be presented as pushed, merged or published code. Follow the repository [commit workflow](../.cursor/rules/commit-workflow.mdc).

## Local checkpoints — 18 October 2026

* `d7a35af` establishes committing coherent, verified milestones with explicit staging and shared-worktree coordination.
* `ee445d2` saves the bounded CLI execution and readable-error dependency, with its seven failure tests. Model-catalog changes are excluded.
* `e6fb4a1` saves the connected Learn implementation, regression tests and captured evaluation fixtures. This initial checkpoint preserves the accumulated work; future changes should use smaller behavior-level commits.

The exact staged tree for `e6fb4a1` was exported into isolated temporary storage and passed **265 macOS tests, zero failures or skips** (`/tmp/cauchy-commit-learning-tests.xcresult`). This excludes the separately owned model-catalog edits and their additional test; earlier 266-test reports below refer to the combined working tree at that time. The evaluator's five offline checks also pass. No new live model calls were made. Native observations retain their narrower recorded scope. These are local commits; no push, merge or release is claimed.

## Source anchors

These are entry points for investigating each issue, not claims that the planned work is implemented.

| Issue | Relevant code and evidence |
| --- | --- |
| [JERRY-115: Preserve unsubmitted prerequisites](https://linear.app/jerryjin/issue/JERRY-115) | [Optional draft history and search](../Cauchy/Models/LearningSession.swift), [fresh-challenge transition](../Cauchy/ViewModels/LearningViewModel.swift), [428-test verification and native observations](evaluation/learning-prerequisite-drafts.md) |
| [JERRY-114: Revise a chapter argument](https://linear.app/jerryjin/issue/JERRY-114) | [Revision state](../Cauchy/Models/LearningSession.swift), [exact local action](../Cauchy/ViewModels/LearningViewModel.swift), [425-test and complete native verification](evaluation/learning-chapter-revision.md) |
| [JERRY-112: Chapter feedback discussion](https://linear.app/jerryjin/issue/JERRY-112) | [Exact feedback context](../Cauchy/Models/LearningClarification.swift), [discussion panel](../Cauchy/Views/Learning/LearningClarificationView.swift), [420-test and native verification](evaluation/learning-chapter-feedback.md) |
| [JERRY-107: Chapter assessment review](https://linear.app/jerryjin/issue/JERRY-107) | [Exact assessment operation](../Cauchy/ViewModels/LearningViewModel.swift), [chapter feedback/results/history](../Cauchy/Views/Learning/LearningSessionView.swift), [416-test and native verification](evaluation/learning-chapter-assessment-review.md) |
| [JERRY-69: Reader/Learn synchronization](https://linear.app/jerryjin/issue/JERRY-69) | [Sync policy](../.cursor/rules/workstream-sync.mdc), [exact inputs and integration evidence](evaluation/workstream-sync.md) |
| [JERRY-50: Native Learn verification](https://linear.app/jerryjin/issue/JERRY-50) | [LearningSessionView](../Cauchy/Views/Learning/LearningSessionView.swift), [LearningStudyMapView](../Cauchy/Views/Learning/LearningStudyMapView.swift), [chapter challenge audit](evaluation/chapter-challenge.md), [source review audit](evaluation/source-reconciliation.md) |
| [JERRY-55: Unavailable chapter recovery](https://linear.app/jerryjin/issue/JERRY-55) | [LearningStudyMap.chapterRequest](../Cauchy/Models/LearningStudyMap.swift), [LearningStudyMapView](../Cauchy/Views/Learning/LearningStudyMapView.swift), [LearningStudyMapTests](../CauchyTests/LearningStudyMapTests.swift) |
| [JERRY-51: Mathematical source correction](https://linear.app/jerryjin/issue/JERRY-51) | [LearningSourceBuilder](../Cauchy/Services/LearningSourceBuilder.swift), [LearningSourceReconciler](../Cauchy/Services/LearningSourceReconciler.swift), [LearningReconciliationTests](../CauchyTests/LearningReconciliationTests.swift), [transcription verification](evaluation/source-transcription.md) |
| [JERRY-53: Proof evaluation](https://linear.app/jerryjin/issue/JERRY-53) | [LearningTutorService](../Cauchy/Services/LearningTutorService.swift), [proof evaluator](../scripts/evaluate_learning_proofs.py), [chapter evaluator](../scripts/evaluate_chapter_challenge.py), [proof evaluation](evaluation/proof-evaluation.md) |
| [JERRY-52: Delayed review](https://linear.app/jerryjin/issue/JERRY-52) | [LearningSession](../Cauchy/Models/LearningSession.swift), [LearningViewModel](../Cauchy/ViewModels/LearningViewModel.swift), [delayed-review verification](evaluation/delayed-review.md) |
| [JERRY-54: Syllabus reconciliation](https://linear.app/jerryjin/issue/JERRY-54) | [LearningStudyMap](../Cauchy/Models/LearningStudyMap.swift), [LearningStudyMapView](../Cauchy/Views/Learning/LearningStudyMapView.swift), [syllabus verification](evaluation/syllabus-reconciliation.md) |
| [JERRY-56: Isolated native verification fixture](https://linear.app/jerryjin/issue/JERRY-56) | [LearningUIFixture](../Cauchy/Services/LearningUIFixture.swift), [isolated launch and native observations](evaluation/learning-ui-fixture.md) |
| [JERRY-57: Delayed-check history labels](https://linear.app/jerryjin/issue/JERRY-57) | [Learning history rows](../Cauchy/Views/Learning/LearningWorkspaceView.swift), [native same-title history verification](evaluation/learning-ui-fixture.md) |
| [JERRY-62: Contextual lesson questions](https://linear.app/jerryjin/issue/JERRY-62) | [Clarification records](../Cauchy/Models/LearningClarification.swift), [focused question panel](../Cauchy/Views/Learning/LearningClarificationView.swift), [verification and live prompt checks](evaluation/learning-clarification.md) |
| [JERRY-61/64: Focused course and questions](https://linear.app/jerryjin/issue/JERRY-61) | [Design refinement](evaluation/learn-design-polish.md), [course view](../Cauchy/Views/Learning/LearningStudyMapView.swift), [session view](../Cauchy/Views/Learning/LearningSessionView.swift) |
| [JERRY-63: Bounded study sessions](https://linear.app/jerryjin/issue/JERRY-63) | [Study-run policy](../Cauchy/Models/LearningStudyRun.swift), [verification](evaluation/study-sessions.md) |
| [JERRY-75: Long content and keyboard actions](https://linear.app/jerryjin/issue/JERRY-75) | [Layout and keyboard checks](evaluation/learning-layout.md) |
| [JERRY-77: Review and chapter focus](https://linear.app/jerryjin/issue/JERRY-77) | [Alternate next-action and chapter checks](evaluation/learning-next-actions.md) |
| [JERRY-78: Concise history and full details](https://linear.app/jerryjin/issue/JERRY-78) | [History and metadata checks](evaluation/learning-history.md), [goal audit](evaluation/learn-goal-audit.md) |

The 17 October local inspection of the saved Metric Spaces inventory found 19 units with no open candidate gap and a proof target wherever required. Only one of its ten chapters contained a connected pair satisfying the current `chapterRequest` source-safety checks. This is a dated availability observation, not a mathematical assessment or a live project status. It motivates JERRY-55; making the feature visible must not waive unresolved obligations.
