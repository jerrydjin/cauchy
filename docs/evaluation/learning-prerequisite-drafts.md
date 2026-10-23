# Keeping unsubmitted prerequisite work — 23 October 2026

[JERRY-115](https://linear.app/jerryjin/issue/JERRY-115) fixes a reproduced loss of learner reasoning. A learner can write a prerequisite answer, return without submitting it, finish the main chapter argument and request a fresh challenge. Previously that successful generation cleared the prerequisite draft without creating any recoverable history. Submitted prerequisites already had their own assessment records.

The added regression fails on `85d4767`: `/tmp/cauchy-prerequisite115-red.xcresult`, with its log and summary alongside it. The fresh generation succeeds, but the draft's marker disappears from both serialized state and local search.

## Behavior

Only after a fresh challenge passes validation and the current source/requirements checks does Learn preserve a nonblank, unsubmitted prerequisite. `LearningPrerequisiteDraft` retains its full answer, original refresher (question, explanation and source reference), original chapter question, stable ID and archival time. Source and chapter requirements remain those of the parent session. Optional `LearningChapterState.prerequisiteDrafts` decodes older records without a migration.

The new prerequisite starts empty. Existing graded prerequisite history stays separate; blank/whitespace-only or already assessed drafts do not create another record. Failed, cancelled, changed-source and obsolete-requirement requests do not archive or clear anything. Earlier archives append without rewriting prior records. No draft is a fabricated assessment, completed topic or independent chapter result. A distinct fresh question retains the existing help reset.

Completed chapter results expose the current **Unsubmitted prerequisite draft**. **Earlier prerequisite drafts** remain available during later questions and results, with question-led rows, full answer, saved date, original chapter question and **Not submitted · no assessment**. These read-only views show the learner's own work and question; they do not reveal the stored tutor explanation, answer key or hints. Local search includes the earlier prompt, chapter question and full draft only. Inspection does not request a tutor, change evidence or record help merely for reading the learner's own answer.

## Automated verification

All **428 macOS tests pass, zero failures or skips**, on final exact inputs: `/tmp/cauchy-prerequisite115-persistence.xcresult`, `/tmp/cauchy-prerequisite115-persistence.log`, `/tmp/cauchy-prerequisite115-persistence-summary.json`. Three new regression methods and an extended source/requirement-generation test cover:

- complete draft and surrounding whitespace retention, exact original question/refresher context, controlled archival time, legacy decoding, rejection of repeated questions and cancellation without writes;
- read-only search, omission of archived keys/hints/tutor explanation, preservation of original assessments, genuinely fresh independent chapter grading and unchanged topic completion;
- no archives for empty, whitespace-only or graded prerequisite work, with existing graded history retained;
- real temporary persistence across two fresh questions and restarts, stable distinct archive IDs, unchanged earlier archive, main assessments, personal exclusion, discussion/follow-up, other saved sessions and entire map; the old draft never becomes the new prerequisite answer;
- rejected late generation after source or chapter-obligation changes, preserving the unsubmitted prerequisite and the complete original session with zero writes.

Validation uses an isolated archive of `85d47672fac8c007284f48e48ccf6ef61d9fe065` in `/tmp/cauchy-prerequisite115-validation` plus four byte-identical implementation/test files in `/tmp/cauchy-prerequisite115-inputs.json`. SwiftMath is pinned to `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`; automatic package resolution is disabled. No new Swift file or project registration is required.

## Native observations and remaining checks

The previously stopped task-owned `/tmp/CauchyChapterFeedback112.app` (`com.cauchy.chapterfeedback112`) runs the tested code against fresh authored root `/tmp/cauchy-ui-fixture-prerequisite115-native`. The previous `chapter114` root remains exactly equal to its final saved snapshot. Initial native dylib SHA-256: `4e0615260c4c85820127fe42c8b1a02d3854594a7d2fbf20b74c8582733ab002`, matching the first 428-test build. Final timestamp-alignment polish also passes all 428 tests; its dylib is `3ca5086c42dee58e2de1308adaa88f76076a74bc8b5217854cdd80b147986493` and has not yet replaced the running app.

Verified with the authored offline tutor:

1. Type a complete 2,119-character prerequisite draft, including leading/trailing whitespace, Unicode notation and beginning/end markers. Return without checking it; only the separate main argument is assessed. Save a feedback discussion, unsent follow-up and personal exclusion on that original Partial result.
2. Completed results expose the full current prerequisite answer and original question, labelled unsubmitted with no assessment. The long content stays readable and left aligned, with one fixed primary fresh-challenge action. Screenshot: `/tmp/cauchy-prerequisite115-current-draft.png`. Pre-generation record: `/tmp/cauchy-prerequisite115-before-fresh.json`.
3. A valid fresh closed-and-bounded question preserves all 2,119 draft characters with exact original refresher context and chapter question. The new argument and prerequisite start blank, with current help false. The original assessment/exclusion, discussion/follow-up, other sessions and map remain unchanged. Only intended current question/envelope, phase, archive/draft/help and recency fields change. Record: `/tmp/cauchy-prerequisite115-after-fresh.json`.
4. Expand the archived question, answer and original chapter question. Full ending marker remains readable. The entire saved sidecar is unchanged by this inspection. Local search for **UNSENT-115-END** finds exactly this chapter, labelled **Your unsubmitted prerequisite draft**; Open lesson returns to the exact fresh argument. Screenshot: `/tmp/cauchy-prerequisite115-search.png`.

Native inspection caught a centered saved timestamp; the final polish aligns it with the rest of the draft. Before cold restart, the native tool reported the Mac locked and automatic unlock failed. Manual unlock has been requested. The app and exact fresh state remain preserved; the attempted edit/quit did not occur, and the sidecar still equals `/tmp/cauchy-prerequisite115-after-fresh.json`. No native cold restart or final independent grading is claimed yet. Remaining checks: save a current argument, quit/cold reopen on the final tested build, confirm exact archives/current draft/recency and final alignment, then confirm independent grading and unchanged topic evidence. JERRY-115 remains In Progress.

Some native accessibility captures fail after a successful action; fresh observations prevent repeating the mutation. A coordinate-based scroll returned `noWindowsAvailable`; the exposed native scroll-page button worked. These are tool observations, not an established product defect. No settings were changed to work around them.

The installed app, normal learner library, reader implementation and system settings remain unchanged. No live model call, push or release occurred. Authored offline grades do not establish mathematical assessment quality or educational efficacy. VoiceOver and alternate appearances remain unverified. [Native export readiness](learning-save-panel-readiness.md) remains separately open as JERRY-106.
