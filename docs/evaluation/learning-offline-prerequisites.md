# Open saved earlier requirements without an assistant

Tracked by [JERRY-128](https://linear.app/jerryjin/issue/JERRY-128), following the [planned-session recovery flow](learning-study-run-recovery.md).

## Problem and change

When a saved plan's current requirement is blocked by earlier work, the session card offers **Open earlier requirement**. Its coordinator could already select an exact saved ordinary lesson without asking a tutor. The card nevertheless always required an available assistant, leaving that local navigation disabled when none was connected.

The card now requires an assistant only when no exact ordinary lesson is saved. `LearningStudyTarget.savedLesson(in:)` is shared by the availability condition and the existing coordinator action. It preserves the coordinator's first-match selection and checks the complete requirement identity: target ID, unit, kind, objective and revision. Course orientation alone does not change identity. Chapter work, delayed checks and unbound sessions cannot substitute for ordinary teaching.

Opening saved work does not resume a paused plan, advance it, create a lesson, mark an assessment or alter either draft. Missing teaching still requires an assistant. Existing busy-state gating and source-recovery routing remain in place. No persistence format, reader behavior, model configuration, layout or glass style changes.

## Automated verification — 25 October 2026

All **449 normal macOS tests pass**, with zero failures/skips and no reported runtime warnings. Two regressions verify:

* Active and paused plans saved through real persistence and reloaded into a document remain blocked by the earlier concept requirement. Its exact local lesson is found and selected by the actual coordinator. The tutor factory is never requested; no learning/map write callback fires. The current proof draft, earlier prerequisite draft, full sessions, map, run state and saved learning-file bytes remain unchanged.
* Earlier requirement versions/wording, different IDs, units or kinds, delayed checks, chapter work and unbound sessions are excluded. Course-context-only changes remain usable. A missing exact lesson keeps the assistant requirement.

The existing suite also covers changed-source recovery, unavailable requirements, direct source inspection, independent evidence, paused-plan restart and reader/Learn persistence compatibility. The ordinary Swift files already exist, so no project regeneration is required.

The isolated archive `/tmp/cauchy-offline128-validation` starts at `16eae8d` and overlays four exact implementation/test inputs recorded in `/tmp/cauchy-offline128-inputs.json`. The passing bundle is `/tmp/cauchy-offline128-final.xcresult`, with `/tmp/cauchy-offline128-final.log` and `/tmp/cauchy-offline128-summary.json`. The standard unoptimized Debug host uses `/Applications/Xcode.app`, pinned SwiftMath `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` and the existing resolved package cache with automatic resolution disabled. Two earlier attempts stopped at test-only stub compilation; neither executed the suite. The corrected final inputs establish the 449-test result.

The exact tested runtime is `/tmp/cauchy-offline128-tested.dylib`, SHA-256 `00a619c6627715fc85a320be15a2154168fce86a51dc60d23ffa7635f493114c`.

## Native verification — 25 October 2026

The dedicated assistant-unavailable native check completed after manual unlock. The earlier upcoming-review app was confirmed stopped and its original runtime/plist were restored before installing this wrapper. See [the cleanup account](learning-upcoming-reviews.md#native-verification--25-october-2026).

The normal development fixture intentionally reports its assistant as available. A separate task-only archive at `/tmp/cauchy-offline128-native-harness` therefore overrides the parent `LearningStudyMapView.assistantAvailable` to `false`, passing the unavailable state to the production study-session card without altering user settings or provider configuration. The four product/test inputs match the passing archive. The one parent-wrapper override and its hash are recorded in `/tmp/cauchy-offline128-native-harness-inputs.json`; it is not a production patch or a claim that the complete wrapper ran the ordinary suite.

The wrapper build succeeds; its log is `/tmp/cauchy-offline128-native-build.log` and pinned runtime is `/tmp/cauchy-offline128-native-harness.dylib` (SHA-256 `37fe2c2a80c2c87ce6822da1a4e58902065d9e6b8f20d461c195182eda7c06fe`).

Two authored saved libraries were used at `/tmp/cauchy-ui-fixture-offline128-saved` and `/tmp/cauchy-ui-fixture-offline128-missing`. Both contain a paused proof item blocked by an earlier concept. The first retains its exact saved concept lesson/draft; the second omits it. Complete before-snapshots are `/tmp/cauchy-offline128-saved-before.json` and `/tmp/cauchy-offline128-missing-before.json`. The saved-case card showed **Your study session is paused** with **Open earlier requirement** enabled while its parent supplied `assistantAvailable = false`. Choosing it selected the exact concept lesson and complete saved prerequisite reasoning. After quitting and confirming process absence, all four complete learning records matched the saved-case snapshot. A cold restart restored that selected lesson and exact reasoning. Returning to the path again showed the paused plan and enabled local action; the original proof draft and plan remained unchanged.

After another confirmed quit, the same runtime was switched to the missing-case root. Its equivalent paused card showed **Open earlier requirement** disabled. The rendered missing-case layout was inspected, then the app was quit. All four missing-case learning records, all four saved-case records and all four preceding upcoming-review records matched their complete parsed before-snapshots at final cleanup. No answer was edited or submitted and no plan was finished or resumed. Automated factory-count assertions, rather than the native window alone, establish zero tutor requests.

Final restoration asserted process absence, then compared the disposable app's original plist and dylib byte-for-byte with the retained pre-check backups. No runtime or root setting was left installed in that app. The check uses a controlled parent availability value; it does not establish every live provider-disconnection path or comprehensive accessibility behavior. The 449-test runtime and this one-override native wrapper remain separately identified above. The normal learner library, installed app, assistant configuration and system settings are unchanged. No live model evaluation, push, merge or release occurred.
