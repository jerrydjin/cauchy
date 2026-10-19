# Bounded study sessions

Tracked by [JERRY-63](https://linear.app/jerryjin/issue/JERRY-63). The requirement is a small on-demand plan with a clear stop, pause/resume and a concise record of actual attempts. Bounding the navigation must never truncate a proof, waive a missing source argument or award learning credit for stopping.

## Policy milestone

`LearningStudyRun` stores at most three requirements. A due delayed review comes first; new work follows the saved path and concept/proof/application order. Repeated chapter references do not duplicate a task. The first source gap remains an actionable stop. Starting a later requirement cannot skip earlier open work or an unlocated proof. This is a conservative path-order policy, not an adaptive model of prerequisite mastery or a guarantee about study time.

Items bind to an existing lesson or a newly assigned lesson ID. Their baseline attempt IDs prevent an old exit result from counting as work in the new session. Progress uses the latest real exit attempt for the exact requirement and work kind. Only a completed, independent correct result advances the plan. Uncertainty, incorrect/partial reasoning and helped answers leave the requirement open. An explicit finish records the actual result or no attempt, and leaves remaining items unfinished. The source lesson, complete proof, answer, help and assessments are untouched.

Plans and summaries are optional records on the existing study map. They use its Learn save callback and survive changed-source rebuilds as blocked history. Source signatures and exact target kind/objective are rechecked before progress. No reader persistence, document schema implementation or provider configuration was changed. Session decoding remains compatible through optional metadata.

The milestone passes **74 targeted macOS tests, zero failures or skips**, including 13 new run-policy tests alongside existing learning-flow and study-map checks (`/tmp/cauchy-study-run-policy-final-tests.xcresult`). Tests cover due-review ordering, source blockers, old and unrelated evidence, latest-question matching, newly assigned lessons, uncertainty/help, prerequisite ordering, complete proof/draft preservation, pause/resume, early finish, changed requirements/source, one active run, legacy decoding and source rebuilding. A test initially expected a global planner error; it was corrected to check the planner’s existing unresolved-page reporting instead. No product error handling was changed for that assertion.

This checkpoint is the policy and persistence foundation. The on-demand plan panel, active-session navigation, end summary and native walkthrough remain required before JERRY-63 is ready for review. No native UI claim or live model evaluation is made for this policy-only milestone.
