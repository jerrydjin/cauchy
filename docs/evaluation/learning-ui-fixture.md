# Isolated native Learn fixture — 18 October 2026 follow-up

`LearningUIFixture.swift` supplies development-only authored notes, lessons, a source-complete chapter, an incomplete chapter, a saved helped draft, a due application review, and a prerequisite refresher. The normal Learn views and production state machines render and persist them. The fixture tutor is deterministic: `fixture correct` returns a correct result, `fixture uncertain` returns uncertainty, and other text returns partial feedback. These outcomes test navigation and evidence handling, **not mathematical grading, learning outcomes or a live model**.

## Launch and isolation

Build the Debug Cauchy scheme, then launch its executable with:

```sh
/tmp/cauchy-learning-build/Build/Products/Debug/Cauchy.app/Contents/MacOS/Cauchy --learning-ui-fixture /tmp/cauchy-ui-fixture-manual
```

The root must be a temporary directory named `cauchy-ui-fixture-<name>`. An existing nonempty directory needs the fixture format marker; symlinks anywhere inside storage are rejected. Choose a new directory to reset or to obtain newly added seeded scenarios. An existing fixture resumes its work rather than being reseeded.

For native automation, a separately named, ad-hoc-signed Debug copy can set `CauchyLearningUIFixtureRoot` in its Info.plist. The inspected copy is `build/verification/CauchyLearningFixture.app`, using `com.cauchy.learning-fixture`. The installed app is not replaced.

Fixture storage uses its own `DocumentPersistenceService` root and a preferences suite derived from the root path. It cannot import PDFs, adopt reader workspaces, synchronize into live readers or choose real providers. Its tutor, planner and source-reviewer dependencies are offline. Cache pruning and normal reader restoration are skipped. Quit flushes the fixture store. Release builds exclude the authored content and controller; a fixture launch request in Release shows an unavailable message without opening the normal reader/library.

## Automated evidence

`LearningUIFixtureTests` checks the launch parser, rejected normal/unmarked/escaping storage, complete and blocked chapters, a seeded due review, refused imports, and a chapter → refresher → original argument journey across a real temporary-persistence restart. Original drafts, question/session identity, fractional scroll position, help and existing learning evidence survive. A fresh challenge can record separate independent chapter evidence without completing topic requirements. This remains a logic/integration check, separate from native observations below.

## Native observations

The uniquely named fixture became controllable through `cua_repl` after earlier normal-bundle capture failures. The initial binding took approximately 125 seconds despite a requested shorter timeout; later state/input calls usually returned in under two seconds. Occasional `noWindowsAvailable` / ScreenCaptureKit -3811 errors were recovered by observing the same confirmed-live process, without relaunching it merely because capture failed.

Observed in the native app on macOS 27.2, using the narrow 1,000-point window width in dark appearance:

* Opened the source-complete chapter from the course and entered an unsent argument.
* Opened its prerequisite sheet, entered an answer and submitted with ⌘Return. Returning with ⌘Return preserved the original question and draft and showed the recorded-help message.
* Quit the fixture through its keyboard command, confirmed the process exited, and cold-launched the same copy. The original draft, exact question, recorded help and previously graded refresher answer/feedback restored in the UI. The persisted session ID remained unchanged and its position was `reasoning`.
* Opened the blocked chapter, inspected extraction and missing/omitted-proof reasons, and used its direct source action. The affected topic expanded and the notes inspector displayed PDF page 2. Reading and review controls remained usable with the sidebar and source inspector open at the narrow width.
* Opened the side-by-side original/transcription sheet, joined an extracted line wrap, supplied a note and explicit comparison confirmation, and saved. Reopening showed the original extraction, revised full-page text and dated correction history with its note.
* Ran the offline source revalidation. The extraction candidate was resolved using the labelled transcription, while the explicitly omitted proof and unavailable chapter remained open. No proof result or learner credit was created by that correction.

Native testing found and fixed a return-focus defect: dismissing the prerequisite sheet left focus on the window. The fix clears the underlying answer focus while the sheet is open and restores it from `onDismiss`. After rebuilding the separate fixture copy, the native recheck returned focus to the original answer editor, with its question and draft intact.

A fresh fixture root additionally exercised:

* The single due application action, a fresh question for the exact seeded target, an unsent delayed draft, quit and cold restart. The same review session, draft, question and scheduling metadata restored. Submitting `fixture uncertain` with ⌘Return displayed **Needs checking** and **Assessment inconclusive**, preserved uncertainty without success credit, and scheduled the next attempt after one day. Returning to the path offered one continuing lesson action.
* Two explicit syllabus items with all three work kinds and a provenance note. Mapping one concept displayed **1 of 6** source obligations and **0** learner-evidence obligations. Marking an absent proof kept its required item visible; reopening and revising the concept mapping retained the earlier decision. The persisted syllabus had two stable requirements and three history entries.
* Original/transcription comparison and confirmed correction again, followed by offline source revalidation. The native issue read **User transcription reviewed**; its evidence disclosure showed **User-verified transcription · revision** with the exact saved UUID. The omitted proof and unavailable challenge remained visible, with zero learning checks on that topic.

The final retained macOS result `/tmp/cauchy-learning-completion-audit.xcresult` reports **266 passed, zero failed or skipped**. Five offline evaluator checks also pass. The final correction audit additionally covers a changed topic anchor and changed existing proof citation, preserving original quotations, target identity and saved work; these last recovery changes are tested through the production validators/state model, not newly exercised through the native fixture. The copied native fixture predates those last anchor/recommendation changes. The production Debug test target includes them.

Nonzero visual scroll restoration, VoiceOver speech and system accessibility preference variants have not been exercised. Fractional scroll persistence is covered by integration tests; the inspected native draft restored at zero scroll offset. Screenshots shown in the chat are actual views of the authored offline fixture and cannot establish live model accuracy.

The final Release build succeeded (`/tmp/cauchy-final-release-audit.log`). Its executable contains none of the fixture format marker, authored development source heading or deterministic assessment token. The fixture request guard remains available to fail closed. Existing unrelated deprecation/actor-isolation warnings remain outside this Learn work.

## Local checkpoint verification — 18 October 2026

Learn is saved in `e6fb4a1`, following the CLI prerequisite `ee445d2`. The exact staged source was exported into isolated temporary storage and passed **265 macOS tests with no failures or skips** (`/tmp/cauchy-commit-learning-tests.xcresult`). The earlier 266-test result included a separately owned additional model-catalog test; those catalog edits were deliberately excluded from this checkpoint. No native observation or live evaluation was rerun merely to create commits. [Work tracking](../work-tracking.md) distinguishes these local checkpoints from publication.
