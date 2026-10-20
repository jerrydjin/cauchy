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


## Provider-readiness handoff after focused sessions

Inputs are Learn `f045ebc` and reader main `18be19553f662ef6e31686aba7d2ba9a86980152` (including merged reader PR #8 and provider PR #10). The original coordinator rehearsed the merge in `/tmp/cauchy-learn-reader-sync-20261018`. Its turn stopped at a usage limit after tests and Release build, before commit/adoption. The Learn workstream verified that terminal state, took sole coordinator ownership and inspected the pending merge and exact results. The shared checkout remained clean throughout; the separate JERRY-75 layout patch was kept outside it.

Resolutions retain document-level and highlight conversations, attachment/source-reference controls and the reader's structured provider recovery. `SelectionThreadViewModel` uses its existing commit path on failure and success so the saved document conversation stays synchronized. A regression exercises that failure/recovery boundary. Learn now observes readiness and initiates its own probe when opened or preferences change, rather than waiting for the reader to initiate one. Verification fixtures skip probing. Tutor, planner and reconciler requests record success/failure for the captured connector/model; cancellation does not grant readiness. Structured provider timeouts retain the page-by-page whole-document mapping fallback. The corresponding injected-provider and fallback regressions are included.

The existing exact combined test bundle reports **344 passed, zero failures or skips** (`/tmp/cauchy-sync-20261019-provider.xcresult`), independently inspected using `xcresulttool`. Release succeeded (`/tmp/cauchy-sync-20261019-provider-release.log`). No implementation changes followed these runs; the completing coordinator only removed one trailing space and added this evidence. The new native smoke opened `/tmp/Cauchy Sync 20261019.app`, showed the two-chapter learning path with delayed review and plan actions, opened/cancelled the bounded plan using Escape, and resumed the original concept draft with its saved hint count. The complete saved Learn JSON matched before/after. This is an offline fixture smoke, not a live provider or reader-interaction evaluation. No system settings changed.

Live remote main was rechecked and had advanced to `49286a04629c97580e4d3686c1b2e1a55ecebd64`. That later reader work is outside this pinned, already-tested handoff and remains a later synchronization input. No remote merge, push, release or publication of Learn is authorized or performed here.
