# A clearer lesson opening — 26 October 2026

Tracked by [JERRY-133](https://linear.app/jerryjin/issue/JERRY-133).

Jerry’s first laptop review found the four numbered stages uninspiring and the starting question confusing. Ordinary lessons now open with a short introduction, a rendered learning goal and a primary **Start with the explanation** action. **Try a question first** explicitly opts into the existing diagnostic. A single activity label replaces the numbered strip throughout ordinary lessons. The question view explains its purpose before showing the original prompt. Goals use the existing rich-text renderer so math delimiters do not appear as literal text.

The introduction appears only for an untouched ordinary diagnostic. Existing answers (including whitespace), attempts, feedback, tutor exchanges and nonempty discussion drafts reopen directly. Choosing the optional question reveals the editor and focuses it. The choice is temporary UI state; the saved lesson, questions, grading and evidence rules are unchanged. Starting with the explanation uses the existing `studyInstead()` transition and creates no assessment. Chapter challenges and delayed checks retain their existing entry flows.

Future lesson generation requests plain learner-facing tasks, separate requests on separate lines, concise objectives and natural labeling of invented examples. Existing prompts remain intact. No live generation evaluation was performed, so this does not establish that every new model reply will follow that guidance.

## Verification

The Debug macOS suite passed **463 tests, zero failures or skips**, with no reported runtime warnings. Result: `/tmp/cauchy-learn-opening-tests.xcresult`; parsed summary: `/tmp/cauchy-learn-opening-summary.json`. Existing compiler warnings in connector setup and App Intents metadata remain outside this change.

Native checks used the separately identified, ad-hoc-signed `build/verification/Cauchy Learn Preview.app`, with the deterministic offline tutor and isolated `/tmp/cauchy-ui-fixture-opening-20261026` library:

- A new passage lesson opened the introduction with no numbered strip, answer editor or disabled submit action. Both entry actions were readable in the inspected dark layout.
- The optional route displayed its purpose, original question and focused editor. Entering an answer enabled submission.
- A confirmed quit and cold restart reopened that exact question and unsent answer directly. The complete saved fixture content matched the pre-restart baseline.
- A second authored untouched lesson rendered inline math in its goal. Command-Return opened the explanation, with no answer, feedback or assessment attempt created.
- After final quit, all earlier session objects and the complete study map matched their baseline. Only the explicitly started lesson advanced to teaching.

A transient ScreenCaptureKit failure on restart was recovered by bringing forward the same running preview’s Learn window, without another relaunch. Alternate appearance, VoiceOver speech and broad accessibility-setting combinations were not exercised. These checks establish the entry behavior and saved-work preservation; they do not establish learning outcomes or mathematical grading quality.
