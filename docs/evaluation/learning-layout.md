# Learn layout and keyboard checks

Tracked by [JERRY-75](https://linear.app/jerryjin/issue/JERRY-75). The user requires a focused, polished Learn experience and has explicitly asked to keep system settings unchanged. No VoiceOver, appearance or display-accessibility settings were changed. Those checks remain unexercised.

## Concrete layout fixes

At a 1000-point window width with the sidebar and source inspector open, the original lesson footer compressed Continue out of sight. Lesson navigation now uses horizontal controls when they fit and a second row for the practice shortcut when they do not. Back and Continue retain their intrinsic size. The [native layout selector](https://developer.apple.com/documentation/swiftui/viewthatfits) chooses between those presentations; there is no second primary action or new content card.

A long question could leave its auto-focused answer editor below the visible viewport while accepting typing. Actual editor changes now reveal the reasoning area. Arriving at a question still shows its beginning; restoring model state does not count as an editor change. Chapter scroll restoration retains its existing path.

The bounded plan still previews two or three requirements. Each row now has a named full-requirement control. It opens the complete title and objective inside the same plan panel, with a scrollable reading area and Back to plan. Space opens a focused requirement; Space/Shift-Space scroll its text, and Escape returns to that requirement control. Tab reaches the next requirement. Each newly opened detail starts at the top. A second Escape cancels the preview. Full details do not rely on hover text, and preview rows use stable target identities.

## Evidence

The changes are limited to the two Learn views on integration baseline `188d560`; its observable provider readiness is retained. **86 targeted macOS tests pass, zero failures or skips**, covering learning flow, study-map policy, bounded runs, temporary persistence/fixture behavior and captured-provider readiness. Result: `/tmp/cauchy-learn-long-polish-verified-tests.xcresult`. These policy tests do not prove visual layout; the following native checks do.

The Debug app was copied into the existing isolated verification bundle and used `/tmp/cauchy-ui-fixture-long-20261019`. The authored fixture was copied with both document URLs pointing at its own temporary PDF, then expanded to a twelve-step proof with long claims/justifications, long questions and long requirement titles/objectives. This exercises layout, not mathematical correctness or live providers. Native inspection used the current dark appearance on macOS 27.2 at the minimum 1000-point window width.

- Read the complete proof through step 12 and its final conclusion marker. Escape returned to the saved part. With source notes open, Back and Continue were visible; a pointer action and ⌘Return each advanced exactly one part. Back restored the original part. The regular wider layout was also inspected.
- Arrived at the beginning of a long question, then typed into its focused editor. The full end-of-question marker and answer editor became visible. The exact typed draft was saved. Proof content, source, assessments and study map matched the pre-check snapshot; no new learning credit was created.
- Opened full requirement 1 with Space, read its complete objective through its end marker and scrolled with Space/Shift-Space. Escape restored focus to requirement 1. Tab reached requirement 2; Space opened its full text at scroll offset zero, and Escape returned focus to requirement 2. Cancelling the preview left the complete saved Learn JSON unchanged and created no plan.
- Inspected the contextual question panel with a long question; its question editor and return action stayed visible. This panel was unchanged by the layout patch.

Artifacts in the chat directory: `learn_narrow_footer_before.png`, `learn_narrow_footer_after.png`, `learn_long_proof_end.png`, `learn_long_question_answer_visible.png`, and `learn_full_requirement_details.png`. Screenshots show authored offline content. Space/Shift-Space were exercised for detail scrolling; other installed keyboard mappings are not claimed as native-tested. Long feedback, active-session/end-record layouts with long titles, and complete keyboard-only journey checks remain part of JERRY-75. Actual VoiceOver and alternate system-setting checks remain outside this run per the user's instruction.

## Active-session and feedback continuation

The long-title session check found a wall of title/goal text ahead of the primary action. Active sessions now show a two-line title and a closed Requirement details disclosure. The full title and objective remain readable there; the visible title retains its full accessibility label. Native inspection confirmed that Continue, chapter exploration and course details are visible together with source notes open. Expanding the disclosure reaches the complete goal's end marker. This view-only change passes the same **86 targeted macOS tests**, zero failures/skips (`/tmp/cauchy-learn-session-disclosure-tests.xcresult`).

For long feedback, the real offline tutor first produced an uncertain practice assessment through the normal submission controls. Only its feedback and next-step strings were then expanded in temporary storage, keeping both the saved current feedback and corresponding attempt consistent. With source notes open, the native view scrolled through both end markers; Revise my answer and Review the idea remained visible. No live-provider or mathematical validation is inferred from authored text.

The session was started through the real two-requirement preview and resumed the existing proof draft. Finishing after practice-only work showed zero exit checks and two planned requirements. Its initially collapsed record kept one return action visible. Expanding it displayed both full long titles, each explicitly left open. ⌘Return acknowledged the summary and returned to the regular next action. Every saved lesson, full proof, draft and assessment matched the pre-finish snapshot; the single uncertain practice attempt was retained and no exit outcome was fabricated. Artifacts: `learn_long_session_before.png`, `learn_long_session_after.png`, `learn_long_feedback_end.png`, `learn_long_session_record.png`.

These continuation checks complete the planned long-feedback and long-title record inspection. Native keyboard verification is limited to the explicitly recorded keys and focus routes; a complete keyboard-only journey, actual VoiceOver and alternate system settings are not claimed. System settings remained unchanged as requested. No reader, provider, persistence policy or assessment behavior changed in this continuation.

## Keyboard access under the existing system settings

The current native Tab behavior did not reach the course/session toolbar controls. Learn now exposes its existing actions in the Learn menu: Show Learning Path (⌥⌘L), Plan a Study Session (⇧⌘P), Pause/Resume Study Session (⇧⌘U), Finish Study Session Here (⇧⌘E), and Show/Hide Source Notes (⌥⌘I). These act on the focused Learn library; they are disabled without the appropriate document or session. Planning keeps its existing course, readiness, busy-state and acknowledged-summary conditions. Pause retains the toolbar's ability to cancel an in-flight tutor; resume waits until the document is idle. Reader commands are unchanged. The plan sheet is owned by the workspace so the menu and course button open the same preview.

The following bounded-session journey used only keyboard actions after launching the isolated native fixture:

- ⇧⌘P opened the plan with the first full-requirement control focused. Escape cancelled it; the complete saved Learn JSON was byte-for-byte unchanged.
- ⇧⌘P followed by Return started exactly one two-requirement session and resumed the existing proof/practice work.
- ⇧⌘U paused and returned to the learning path. After ⌘Q and a fresh launch, the paused state was restored. ⇧⌘U resumed the same proof with its exact `fixture uncertain` draft and existing feedback.
- ⌥⌘I opened the source inspector; ⌥⌘L returned to the path. ⇧⌘P had no effect while the run was active, matching its disabled menu item.
- ⇧⌘E finished the session and displayed zero exit checks/two planned requirements. ⌘Return acknowledged it and restored the regular next action. The menu then enabled planning and disabled pause/finish. Selecting its Plan item also opened the same preview; Escape cancelled.

The final saved state contains exactly one additional finished/acknowledged run with no fabricated item outcomes. All lesson fields, proofs, drafts and assessments match the pre-check snapshot except the expected `updatedAt` timestamp changed by opening source notes. Pausing alone preserved the complete session array exactly. Snapshot files are temporary authored fixture evidence, not learner data.

This proves the new bounded-session keyboard route under the existing settings, alongside the earlier detail-reading, lesson-navigation and contextual-question checks. It does not establish an exhaustive keyboard audit of every historical course tool, actual VoiceOver operation or alternate display settings. System settings remain unchanged per the user's explicit constraint. Native menu screenshot capture was unavailable; no menu screenshot is claimed.

The final visual audit also caught a remaining wall of title text in the regular next-lesson recommendation. Its title now uses two lines with a full accessibility label; the complete selectable title lives with the existing Lesson goal details. In the rebuilt native app at 1000 points with source notes open, Continue, planning, chapter exploration and Course details remain visible. Expanding Lesson goal displays the complete long title. Artifact: `learn_compact_recommendation.png`. Opening/cancelling the preview and reading these details leaves the complete saved Learn JSON unchanged.

Validation: **344 combined macOS tests pass, zero failures or skips** (`/tmp/cauchy-learn-menu-final-tests.xcresult`) on the final menu actions and guards. The subsequent title-only adjustment builds successfully (`/tmp/cauchy-learn-menu-title-build.log`) and was inspected natively, including the plan shortcut, initial requirement focus and Escape dismissal. No test was added that mirrors menu/view implementation. The shared integration's reader conversations, source-safety rules and assessment policy remain intact.
