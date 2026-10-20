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
