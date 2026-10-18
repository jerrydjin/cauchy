# Reader/Learn checkpoint synchronization — 18 October 2026

Tracked by [JERRY-69](https://linear.app/jerryjin/issue/JERRY-69). This is a verified local development baseline, not a GitHub merge, Learn publication or release.

## Inputs

| Workstream | Exact input |
| --- | --- |
| Committed Learn baseline | `e29c97ee42b9d1173410dcf20cca2145c098bdae` |
| Verified contextual-question checkpoint | `0ad339a` |
| GitHub reader main | `42e1f78` |
| Reader reference-hover PR #6 | `395aaecba42fbbd8591f5671a9b42341ac7b7316` |
| Reader Ask/attachment PR #7 | `b999fecd430db1fe5e14a84c6b495db7438049a6` |
| Reader reliability/model/accessibility PR #8 | `7d7d1ca2240e19f49af91ff5eb8978ec10b376a0` |

All three reader PRs had passing GitHub build/test checks when inspected. Their heads were still open PRs. Reader main already contains the website refresh and download/documentation changes. The contextual-question milestone was incorporated only after its owner finished verification and committed `0ad339a`.

The rehearsal used `codex/learn-reader-sync-20261018` in a separate temporary worktree, leaving the shared checkout untouched while its owner worked. The added persistence regression uses authored temporary workspace data and makes no live model requests. The final coordinated handoff is recorded below.

## Conflict and regression

Reader main and PR #6 merged cleanly. PR #7 produced one textual conflict in `WorkspaceViewModel.persistWorkspace`: reader Ask adds its document conversation while Learn synchronizes its saved sessions/map. Both are required. The resolution assigns the reader conversation ID and messages first, then calls `learningLibrary.synchronize`, ensuring the Learn snapshot also contains the current reader fields.

The existing alternating reader/Learn persistence regression now verifies the whole-document conversation ID and messages alongside the learner draft and annotation. It closes the reader, edits Learn, and loads through a fresh persistence instance. The reader question and learner draft must both survive. This tests integration at the actual shared save boundary without contacting a model.

The combined Learn, reader-main, PR #6 and PR #7 tree passed **291 macOS tests, zero failures or skips**, with Xcode's macOS 27 SDK (`/tmp/cauchy-sync-ask-tests-20261018.xcresult`). PR #8 then merged without a textual conflict, but compilation found two copies of `CodexFailureTests`: the same CLI prerequisite had arrived through independently checkpointed histories. Their bodies were compared and confirmed identical. One duplicate was removed; all seven distinct CLI failure tests remain.

The resulting preview passes **292 macOS tests, zero failures or skips** (`/tmp/cauchy-sync-reader-recheck-20261018.xcresult`). Whitespace checks also pass. This does not verify the complete combined native UI or the contextual-question changes still being finished in the shared checkout. Separate green PR checks alone would not have caught either integration issue.

## Sync boundary

The Learn owner finished its contextual-question and keyboard milestone, committed `0ad339a`, and agreed to hold further edits during handoff. That commit merged into the preview without conflicts. The full combined tree passed **304 macOS tests, zero failures or skips** (`/tmp/cauchy-sync-clarification-tests-20261018.xcresult`), checkpointed as `cec0fb2`. The source milestone's own native observations remain documented in [learning clarification](learning-clarification.md); this combined run is not a new native UI audit.

The seven previously pending reader/website files were then preserved as `ea9e786` on the shared branch. All four reader code/test files matched the published PR #8 snapshot byte-for-byte. The image matched GitHub main, and every added website line already existed there. Reconciliation kept the newer GitHub website `figure` layout and its identical image metadata rather than restoring the older wrapper. The staged tree was compared with `cec0fb2` and was identical, so no additional code test run was needed.

The resulting integration checkpoint `adcb283` was adopted by a coordinated **fast-forward** of shared local `main`. No reset, stash, branch switch or history rewrite was used. The untracked local design skill was preserved, and the shared index is empty. Reader PR #6/#7/#8 remain separate public review decisions; no GitHub merge, push of Learn or release occurred. Refresh and retest changed remote heads at future verified milestones under the [sync policy](../../.cursor/rules/workstream-sync.mdc).

The adopted combined source also builds successfully in **Release** (`/tmp/cauchy-sync-release-build-20261018.log`). A final live remote-ref check found reader main and all three PR heads unchanged from the pinned inputs. The handoff therefore covers the exact recorded source, not an assumed later remote revision.
