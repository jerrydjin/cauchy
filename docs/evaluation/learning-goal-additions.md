# Learner-added study goals

Tracked by [JERRY-131](https://linear.app/jerryjin/issue/JERRY-131), extending [goal revisions](learning-goal-revision.md) and the saved goal-history flow.

## Result

Each mapped topic offers **Add study goal**. A learner chooses a concept, proof or application requirement, writes the omitted ability and records a reason. The addition retains the topic title, source page and quote, date and any actual verified-transcription ID. It receives a new unchecked requirement identity; existing lessons, answers and grades do not count toward it. The source reference establishes provenance, not that the learner's wording is mathematically correct or fully supported.

An additional proof goal requires an already usable source proof requirement, no open source issues, and matching proof evidence in the actual current PDF/transcription. Unsupported proof kinds are absent from the native menu, with an explanation. Source-review topics cannot add goals. Concept/application additions cannot remove source gaps or supply a missing proof. The raw source inventory remains authoritative for missing-proof detection even if imported addition metadata claims otherwise.

Added goals participate in the existing study choices, lesson preparation, study-plan requirements and chapter identity checks. Earlier chapter work remains saved under its earlier requirements. A learner can revise an added goal using the existing versioned flow. **Review goal changes** combines additions and revisions, distinguishing current, earlier-goal and earlier-source records. Same-source retries retain decisions; source rebuilds archive them without applying them to new requirements. Recovery history does not require a composed course or assistant. Optional Codable fields preserve legacy decoding without a document-schema or persistence-service change.

## Automated verification — 26 October 2026

Six regressions extend the existing 452-test suite. They cover:

* Distinct concept/proof/application identities, unchecked evidence, unchanged raw source obligations, study choices, legacy nil fields and Codable round-trip.
* Missing-proof and unresolved-gap preservation, source-review rejection, and imported proof metadata that cannot replace a located argument.
* Actual transcription provenance and rejection of fabricated source-proof references.
* Empty/oversized wording and reasons, normalized same-kind duplicates, stale topics, busy mapping and changed PDFs, with no rejected-edit writes.
* Addition plus revision history through same-source retries and source-change archival without duplicate archives.
* Real offline lesson preparation and persistence restart: existing sessions/drafts remain intact, a new goal creates separate work, chapter request identity changes, reasons stay out of the tutor inventory, and archived additions remain readable without a course.

All **458 normal macOS tests pass**, with zero failures/skips and no reported runtime warnings. The authoritative final results are `/tmp/cauchy-goals131-menu-final.xcresult`, `/tmp/cauchy-goals131-menu-final.log` and `/tmp/cauchy-goals131-menu-final-summary.json`.

The isolated archive `/tmp/cauchy-goals131-validation` starts at `8604849` with five declared source/test overlays in `/tmp/cauchy-goals131-inputs.json`; their hashes still match the checkpoint inputs. The standard unoptimized Debug host uses `/Applications/Xcode.app`, SwiftMath `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` and the existing resolved package cache with automatic resolution disabled. No ordinary Swift files were added, so project regeneration was unnecessary. An initial build caught and corrected a test-only navigation reference. All 458 tests passed before and after the native Picker correction.

## Native verification

Native checks use the disposable app and a separate authored offline fixture at `/tmp/cauchy-ui-fixture-goals131-native`. The fixture copies earlier authored lessons and includes an explicitly omitted-proof topic. No live model evaluation or normal learner library is involved.

The initial tested build showed a readable editor with source disclosure, a required reason and an initially disabled save button. Cancelling left the complete parsed learning record unchanged. Saving one concept goal showed **Goal added by you · Not checked**; revising it showed **Goal added and revised by you · Not checked**. All existing sessions and source inventories remained unchanged. The native menu revealed that disabling a tagged Picker text did not prevent selecting it on this macOS build; the save/model gates still rejected unsupported proof additions. The final implementation omits that unavailable kind from the menu.

The final exact tested runtime `/tmp/cauchy-goals131-menu-final-tested.dylib` has SHA-256 `0f0734b232cbd6ada67bdf64f69318ef7e39f774e1bd3107e856222b47d788c4`. On that build, the omitted-proof topic's kind menu offered only concepts and application. Saving an application added a second unchecked requirement while its original source gap and unavailable chapter challenge remained. The unified history displayed the new application, revised concept and original concept addition separately. The original addition retained its reason and page/quote; a visual inspection confirmed a readable two-pane history layout.

The copied fixture initially retained an escaped JSON URL pointing to its earlier temporary root; the fixture guard refused to open it. The app was quit, task-owned URLs were corrected through parsed JSON, and the fixture then opened normally. No guard was bypassed and the source fixture was unchanged.

Comparisons with `/tmp/cauchy-goals131-native-before.json` established that two additions and one revision changed only their expected map metadata and update date. All three original sessions, drafts, assessments, raw targets, proof obligations, gaps, course and page records remained unchanged. After a confirmed quit, a cold restart on the final build reopened history with all four decisions, including the earlier fixture revision. The current concept revision still exposed its preceding wording and source reference. The complete learning file matched `/tmp/cauchy-goals131-native-final.json` and its SHA-256 snapshot byte-for-byte after restart/history inspection and final quit.

Cleanup asserted process absence inside the restoration command, then restored the disposable app's original plist and dylib byte-for-byte from `/tmp/cauchy-goals131-original.info.plist` and `/tmp/cauchy-goals131-original.dylib`. The installed app, normal learner library, reader and system settings remain unchanged.

These checks establish the stated source/identity/persistence behavior, not mathematical grading quality, improved learning outcomes or comprehensive accessibility. No push, merge or release occurred.
