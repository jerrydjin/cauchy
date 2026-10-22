# Current requirements and earlier learner work

Tracked by [JERRY-90](https://linear.app/jerryjin/issue/JERRY-90). A saved study plan already stopped when objective wording changed, but current course evidence, review selection and lesson reuse mainly matched target IDs. An earlier correct answer could therefore satisfy a revised objective sharing its ID, and an earlier delayed draft could lead the revised requirement's review queue.

`LearningStudyTarget.matchesRequirement` now compares target ID, unit ID, kind and exact objective. Course context is deliberately excluded: reorganizing a chapter or changing its overview does not change the requirement. This shared rule governs ordinary and delayed evidence, next-study recommendations, delayed-review scheduling/resumption, saved-lesson reuse, study-plan item binding/validation and syllabus references. The lesson coordinator resolves the current unit before acting and rejects a stale target. Source corrections and assessment/help checks still apply separately.

A changed objective starts unchecked and offers **Study**. Its path status explains that the requirement wording changed and earlier work is saved. Old results, schedules and drafts are retained but cannot count toward or resume as the new objective. No saved lesson, attempt, feedback, help flag, date or outcome is migrated or rewritten.

Requirement history deliberately keeps earlier wording grouped under the same target ID, unit and kind. **Review my work** still shows original questions, answers, drafts, feedback and the earlier objective, and **Open saved lesson** opens that original record. A blocked historical plan still resolves its own pinned task and saved work for inspection. Repeat-question exclusion also retains earlier wording's generated prompts; seeing an old question remains relevant even when its answer cannot earn current credit.

## Verification — 22 October 2026

Before the fix, the new revised-objective regression failed against `aaa4dc4`: the revised target received the earlier independent correct attempt (`/tmp/cauchy-requirement90-before.xcresult`). The test also exercises old due scheduling, an unfinished delayed draft, completed delayed evidence, next-study selection and new-plan binding. The fixed focused suite passes 28 tests.

The final complete macOS suite passes **392 tests, zero failures or skips**, with no reported runtime warnings (`/tmp/cauchy-requirement90-final.xcresult`, `/tmp/cauchy-requirement90-final.log`). Three new regressions cover:

- revised wording receiving no old credit, delayed evidence, due queue entry or saved-session plan binding, while history retains the original records;
- distinct target/unit/kind/objective identities, matching-question-kind and pinned-ID bypass attempts, and positive reuse/credit when only course context differs;
- the persisted document flow: revise concept/application requirements, retain old correct work and a delayed draft, reject stale lesson/review requests, create a separate current lesson, save its draft, cold-reload and reuse that same record. Every earlier session field and the current map remain intact.

Tests use an isolated archive of `aaa4dc4` plus eight byte-identical implementation/test inputs in `/tmp/cauchy-requirement90-validation`. SwiftMath remains pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`; automatic package resolution is disabled against the existing resolved package cache. No new files require project regeneration. `git diff --check` passes.

Native checks use the production build in `/tmp/CauchyLearnSearch84.app` (`com.cauchy.learn-search84`), with a fresh disposable authored library at `/tmp/cauchy-ui-fixture-requirement90-native`, in the existing 1000-point dark window. The ordinary fixture initially showed a valid correct application check as due. A native **Try a delayed check** created an application review; an authored draft was entered and saved. With the app closed, only the map's concept/application objective wording and update time were revised, preserving the target IDs and all three saved sessions.

After reopening:

- The path led with **Start next lesson**, rather than the old delayed draft or old concept practice. The chapter showed zero of six checks; the application topic showed zero of three, its revised objective, the changed-wording explanation, **Study** and **Review my work**.
- Application history retained the original Correct entry and the unfinished delayed draft. **Earlier requirement wording** showed the original objective. Opening the correct entry retained its original question, answer and feedback. Comparing the complete sidecar before/after inspection showed no changes to any session or the revised map.
- **Start next lesson** created a separate concept session at Starting point with the revised objective. An authored answer was saved. A cold restart restored it; the path's **Continue lesson** reopened the same record and draft. The four-session sidecar remained identical after this navigation, and every field of the three earlier sessions plus the entire revised map equalled the pre-study snapshot.

The final full-suite build was also reopened to confirm the restored draft, current lesson action, zero inherited checks and changed-wording status. Screenshots `/tmp/cauchy-requirement90-path.png` and `/tmp/cauchy-requirement90-history.png` were inspected for readable status, controls, original wording and retained feedback. The installed app, normal library and system settings were unchanged. These are identity, persistence and offline navigation checks, not evidence of mathematical grading accuracy, adaptive mastery or real-model teaching quality. VoiceOver speech and alternate appearance/accessibility settings remain unexercised.
