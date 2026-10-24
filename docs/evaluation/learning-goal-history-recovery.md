# Goal history during path recovery

Tracked by [JERRY-118](https://linear.app/jerryjin/issue/JERRY-118). Native inspection of `0f16d48` reproduced a gap in the new goal-revision flow: a map with archived decisions but no composed course showed preparation details with no route to those decisions. The sidecar retained them. Their visibility depended on successfully composing a course again.

**Review goal revisions** now opens a focused read-only history sheet from preparation details, course details and the blocked planned-session view shown when no course is available. Course details uses this action instead of expanding every historical decision into the path. The sheet offers a concise selectable list beside a scrollable reading pane. It preserves the original wording, new wording, reason, date, topic and source reference.

`LearningGoalHistory` projects three explicit states from the saved map:

* **Current goal** only when the decision's exact target version remains one of the unit's effective requirements.
* **Earlier goal** for superseded or no-longer-applied decisions. Matching wording alone cannot make a retained decision current.
* **Earlier source** for archived decisions retained through source rebuilding. The reading pane explains that their page references may differ from the current PDF.

Records sort by descending decision date, with an ID tie-break for stable navigation. The projection does not require a composed course, tutor availability, learner evidence or a model request. Opening history does not initiate preparation, finish a study session, change a goal or write learning state. The reading pane supports Command-R to move between list and reading focus, keyboard selection, Space/Shift-Space paging and Escape to close. Selection changes return the reading pane to its top; selection is retained if asynchronous map updates keep that record available.

## Automated verification — 24 October 2026

The final complete isolated macOS suite passes **439 tests, zero failures/skips and no reported runtime warnings**. Two new tests cover:

* current, superseded, unapplied and earlier-source decisions with no course; stable date/ID ordering, a reversal of wording with a distinct version, complete retained fields, empty history, round-trip preservation and a missing preceding revision that cannot become current;
* the actual fixture/persistence service saving and reloading archived history with no course or units. Original goals, reasons and source references remain readable without a tutor, and complete sessions/map remain equal to their persisted representations through another save/reload.

The first 439-test run passed. A repeat after small UI additions exposed a redundant direct `Date` equality assertion in the preceding milestone's real-persistence test: **438 passed, one failed**. The same test's canonical complete-map and complete-session assertions passed; only the duplicate comparison of raw in-memory revision dates failed after conversion to the persistence timestamp representation. It now checks revision identity explicitly while the existing canonical comparison continues to cover every map/revision field at the format's precision. No product timestamp or persistence code changed. Final results are from the corrected test and final UI, not the earlier passing build.

Exact inputs: archive of `0f16d48` plus four byte-identical Swift implementation/test files in `/tmp/cauchy-goal118-validation`, recorded by `/tmp/cauchy-goal118-inputs.json`. SwiftMath remains pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`; existing resolved packages are used with automatic resolution disabled. Final result bundle `/tmp/cauchy-goal118-verified.xcresult`, log `/tmp/cauchy-goal118-verified.log`, summary `/tmp/cauchy-goal118-verified-summary.json`. Earlier-run inputs/results remain separately retained. No new source files require project regeneration. `git diff --check` passes.

## Native verification

All app interaction used the native computer-use tool. A known disposable app identity was reused only after confirmed process stops. The final 439-test runtime is pinned at `/tmp/cauchy-goal118-tested.dylib`, SHA-256 `8ad41969df192f20a51ed78b7abffd5b19d771119e7c0df49e2bc76baf2c4090`. The temporary app's original dylib and Info.plist were backed up before changing its fixture root. The installed app and normal library were not used.

Three separate authored roots retain the three sessions from the prior goal-revision check. Their workspace base records are neutralized so that their exact learning sidecars, rather than a stale embedded map, are loaded. The additional recovery, long-history and planned-session states are authored fixture inputs; they are not claimed to have been produced by a live model.

### Preparation and cold restart

`/tmp/cauchy-ui-fixture-goal118-recovery` contains one archived revision, no units/course and two pending pages. On the preceding runtime, opening preparation **Details** exposed no history action. Capture: `/tmp/cauchy-goal118-missing-history.txt`.

On the final runtime, preparation **Details → Review goal revisions (1)** opens the retained decision immediately. **Earlier source** and its page-reference qualification are readable. Expanding **Previous goal and source reference** shows the original application goal and PDF-page-1 quotation. Command-R changes the footer to **Choose another revision**; Escape returns to preparation without starting its Continue action.

The complete learning sidecar equals `/tmp/cauchy-goal118-before.json` after inspection and actual Cmd-Q. The process was confirmed stopped, then cold-reopened. Details/history again shows the same complete reason, date, goal and source reference. Further inspection and quit leave that entire sidecar unchanged. Screenshot `/tmp/cauchy-goal118-recovery.png` was inspected for readable content and visible footer controls.

### Long history and keyboard reading

`/tmp/cauchy-ui-fixture-goal118-history` has a normal composed course with 18 decisions: one current, one earlier in the active goal's chain and 16 archived source decisions. The current decision includes a 1,699-character authored reason with `HISTORY-118-START` and `HISTORY-118-END` markers. Course details offers **Review goal revisions (18)** without expanding all records into the path.

The history opens with the latest record selected and correctly labelled **Current goal**. Down selects the preceding **Earlier goal**, whose pane explains that it does not replace the current goal. Returning to the current record and using Command-R moves to reading focus. Space scrolls to the visible ending marker; Shift-Space returns to the top. Command-R restores list focus. Arrow selection reaches an **Earlier source** record with its distinct qualification and resets the reading pane. Continuing with Down reaches the oldest record; the list scrolls to its bottom while Close and the reading-focus control remain visible.

Screenshots `/tmp/cauchy-goal118-long-reading.png` and `/tmp/cauchy-goal118-oldest.png` were inspected. The complete sidecar, including all 18 decisions, all three sessions and every source obligation, equals `/tmp/cauchy-goal118-history-before.json` after closing history and quitting. A tool key named `PageDown` was rejected before input; the native paging claim here is limited to the verified Space/Shift-Space flow.

### Blocked planned session

`/tmp/cauchy-ui-fixture-goal118-blocked` contains an active pinned study item, no current course/units and one archived goal decision. The path shows the existing changed-requirement explanation, **Review current source**, **Inspect saved work**, **Finish session here** and the new **Review goal revisions (1)** action. Opening history reads the archived decision without finishing or altering the plan. Escape returns to the same blocked item and actions. The complete sidecar equals `/tmp/cauchy-goal118-blocked-before.json` after quit. Screenshot `/tmp/cauchy-goal118-blocked.png` records the access point.

The disposable app is left stopped; its earlier Info.plist and dylib are restored byte-for-byte. Both the original goal-revision fixture and the protected prerequisite-draft fixture remain equal to their prior verified snapshots. No system settings, reader behavior, installed-app state or normal learner data changed.

These checks establish recovery access, read-only preservation and the stated native keyboard/layout behavior. They do not establish mathematical quality, an exhaustive accessibility audit, live-model behavior, native concurrent rebuilding while the sheet remains open, alternate appearance settings or native Page Up/Page Down handling. No live model evaluation, push, merge or release occurred.
