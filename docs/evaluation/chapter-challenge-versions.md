# Current and earlier chapter challenges

Tracked by [JERRY-91](https://linear.app/jerryjin/issue/JERRY-91). Preparing a chapter challenge previously reused the first saved session with the same module ID, even when its requirements or source had changed. The document's generation-freshness callback checked only that the old units still existed without open gaps; it did not compare the actual current chapter or selected argument.

A saved challenge now belongs to the selected connected argument and its teaching requirements. `LearningChapterRequest.hasSameRequirements` compares the module, directed pair, connection, exact target identities, prerequisites, source anchors/pages, proof obligations/evidence and transcription identities, with both snapshots source-complete. Display titles and course context alone do not create another challenge. `LearningStudyMap.isCurrentChapterRequest` derives the current eligible request, so removed chapters, changed connections, incomplete pages, changed requirements and reopened source obligations cannot authorize new or refreshed generation. The existing post-response check uses the same current-path decision.

Reuse also requires the current source. A changed request or source creates a separate session; earlier questions, answers, feedback, help, dates and source remain in the original record. The chapter now offers its current **Try the chapter challenge** / **Continue chapter challenge** action beside an **Earlier challenges** menu. Earlier work no longer takes the current chapter's place in next-action selection. Saved arguments outside the current requirements have an **Earlier learning path** explanation and **Open current learning path** action. An unfinished original argument can still be answered against its unchanged original source; a completed earlier argument returns to the current path for further challenges. Existing changed-source recovery still takes precedence when the PDF/transcription itself is stale.

New and refreshed challenges exclude displayed or attempted questions from the same module or the same pair of units, including earlier saved versions. Returned exact repeats are rejected before saving. This prevents a source/version change from treating a previously shown problem as fresh; it does not establish semantic novelty, transfer or mathematical alignment.

Native verification exposed an additional recency problem: focusing an already-saved chapter position wrote it again and changed `updatedAt`. Position and scroll setters now skip unchanged values. Actual navigation still persists; merely reopening the same saved position no longer changes the record's recency.

## Verification — 22 October 2026

The corrected before-fix regression failed against `daf009f`: the real document callback accepted the earlier chapter request, and a revised request reused its old draft (`/tmp/cauchy-chapter91-before3.xcresult`). The first focused fixed suite passed 23 tests before the final cross-version freshness and unchanged-navigation checks were added.

The final complete macOS suite passes **397 tests, zero failures or skips**, with no reported runtime warnings (`/tmp/cauchy-chapter91-final2.xcresult`, `/tmp/cauchy-chapter91-final2.log`). Five new regressions cover:

- a changed target objective within stable chapter/unit IDs creating a separate challenge, retaining its earlier draft and rejecting the stale request;
- matching through harmless display/context changes, and rejection after connection, unit, transcription identity, source-obligation or page-availability changes;
- changed-source replacement, rejection of a repeated old question, preserved old work and reuse of the current-source record;
- persisted earlier assisted feedback/refresher work plus a new current draft, rejected old-scope refresh, cold reload and current-record reuse without individual-topic credit;
- no writes or recency changes for unchanged chapter position/offset, while a real offset change still saves.

Tests use an isolated archive of `daf009f` plus seven byte-identical implementation/test inputs at `/tmp/cauchy-chapter91-validation`. SwiftMath remains at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`, using the existing resolved package cache with automatic package resolution disabled. No project regeneration was needed. `git diff --check` passes.

The final production build was exercised in `/tmp/CauchyLearnSearch84.app` (`com.cauchy.learn-search84`) with disposable authored library `/tmp/cauchy-ui-fixture-chapter91-native`, in the existing 1000-point dark window. An initial native challenge was prepared, an original argument saved and outside help recorded. With the app closed, only one concept objective and the map update time were revised; the module, unit and target IDs remained unchanged.

- Reopening the original challenge showed **Earlier learning path**, its original question/draft and checked help flag, and a direct current-path action.
- The expanded chapter offered a current challenge alongside **Earlier challenges (1)**. Selecting the menu entry reopened the original record. After the unchanged-navigation fix, complete sidecar comparison confirmed every field of all three earlier sessions, including `updatedAt`, and the entire current map remained identical.
- Preparing the current challenge created a fourth record with the revised requirements, a different supplied-source question and no inherited help. Its independent draft was entered and saved. All fields of the three earlier records and the map still equalled the pre-study snapshot.
- A cold restart restored the new question and draft. The chapter offered **Continue chapter challenge** and its earlier-version menu. Continue reopened the same current record without creating another session. All four full session records and the complete map remained identical after this navigation. The existing one of six individual checks did not change.

Screenshots `/tmp/cauchy-chapter91-earlier.png`, `/tmp/cauchy-chapter91-menu.png` and `/tmp/cauchy-chapter91-current-and-earlier.png` were inspected for readable explanation, native menu labels and separate current/history actions. Menu actions can settle after the first accessibility snapshot; verification observed the resulting document before sending further keys. An early stray Return edited only the disposable draft; the authored snapshot was restored before the final preservation checks.

Source-only replacement, late generation rejection and completed historical feedback preservation are automated checks; this native pass revised requirements on an unchanged authored PDF. No live model evaluation, learner-outcome study, VoiceOver speech or alternate appearance/accessibility settings were exercised. The installed app, normal library, reader and system settings were unchanged. Current eligibility describes source-supported navigation, not chapter mastery.
