# Reader/Learn integration rehearsal — 18 October 2026

Tracked by [JERRY-69](https://linear.app/jerryjin/issue/JERRY-69). This is a local integration preview, not a GitHub merge, Learn publication or release.

## Inputs

| Workstream | Exact input |
| --- | --- |
| Committed Learn baseline | `e29c97ee42b9d1173410dcf20cca2145c098bdae` |
| GitHub reader main | `42e1f78` |
| Reader reference-hover PR #6 | `395aaecba42fbbd8591f5671a9b42341ac7b7316` |
| Reader Ask/attachment PR #7 | `b999fecd430db1fe5e14a84c6b495db7438049a6` |
| Reader reliability/model/accessibility PR #8 | `7d7d1ca2240e19f49af91ff5eb8978ec10b376a0` |

All three reader PRs had passing GitHub build/test checks when inspected. Their heads were still open PRs. Reader main already contains the website refresh and download/documentation changes. Current contextual-question work in the shared Learn checkout is outside the baseline above until its owner checkpoints it.

The rehearsal uses `codex/learn-reader-sync-20261018` in a separate temporary worktree. The active shared checkout, its branch, index and pending source files are untouched. No real notes, learner answers or saved workspace records are used in this integration test.

## Conflict and regression

Reader main and PR #6 merged cleanly. PR #7 produced one textual conflict in `WorkspaceViewModel.persistWorkspace`: reader Ask adds its document conversation while Learn synchronizes its saved sessions/map. Both are required. The resolution assigns the reader conversation ID and messages first, then calls `learningLibrary.synchronize`, ensuring the Learn snapshot also contains the current reader fields.

The existing alternating reader/Learn persistence regression now verifies the whole-document conversation ID and messages alongside the learner draft and annotation. It closes the reader, edits Learn, and loads through a fresh persistence instance. The reader question and learner draft must both survive. This tests integration at the actual shared save boundary without contacting a model.

The combined Learn, reader-main, PR #6 and PR #7 tree passed **291 macOS tests, zero failures or skips**, with Xcode's macOS 27 SDK (`/tmp/cauchy-sync-ask-tests-20261018.xcresult`). PR #8 then merged without a textual conflict, but compilation found two copies of `CodexFailureTests`: the same CLI prerequisite had arrived through independently checkpointed histories. Their bodies were compared and confirmed identical. One duplicate was removed; all seven distinct CLI failure tests remain.

The resulting preview passes **292 macOS tests, zero failures or skips** (`/tmp/cauchy-sync-reader-recheck-20261018.xcresult`). Whitespace checks also pass. This does not verify the complete combined native UI or the contextual-question changes still being finished in the shared checkout. Separate green PR checks alone would not have caught either integration issue.

## Sync boundary

The current Learn agent is finishing its contextual-question milestone and a keyboard activation issue found in native verification. Use that verified commit as the next candidate input, then rerun the combined checks before adopting a development baseline. Do not pull into its dirty checkout merely because the separate reader PRs have green CI. Pending reader PRs can be rehearsed locally while their owning workstream reviews and lands them.
