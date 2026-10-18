# Learn design refinement — 18 October 2026

## Next action before course administration (JERRY-61)

The course opens with its title and one existing recommendation. Chapters follow. Overview, source review, syllabus comparison and coverage now share a collapsed **Course details** group. Its label retains the count of open source issues and unresolved pages when present. Retrying unresolved pages lives with coverage. A source blocker on the recommended lesson still has its direct source action; chapter recovery and source-safety gates are unchanged. A delayed check’s explanation is attached to **About this check** rather than a standing paragraph.

The grouping follows Apple’s current [disclosure guidance](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls): keep frequent controls visible and disclose less-used details in context. Content uses semantic backgrounds; the existing primary glass control is preserved, consistent with the [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). Both Markdown pages were read on 18 October 2026.

Validation used an isolated source snapshot: HEAD `972056b` plus the Learn changes, excluding the shared checkout’s unrelated reader, connector and website edits. Xcode 27.1 built with the macOS 27.2 SDK. `/tmp/cauchy-course-focus-tests.xcresult` records **265 passing tests, zero failures or skips**. This predates the development notice’s final footer placement; the final fixture isolation/restart tests are recorded separately below. No new tests were added for display ordering.

The separate native app `build/verification/CauchyLearnPolish.app` (`com.cauchy.learn-polish`) uses `/tmp/cauchy-ui-fixture-polish-20261018`. The original installed app and its notes were not replaced. Its existing offline fixture is authored verification content, not a demonstration of mathematical grading or live model output.

Native observations in the 1,000-point dark window:

- The due application check appears before chapter navigation and Course details. There is one prominent learning action.
- Course details reveals Overview, Source review, syllabus comparison and coverage. Coverage retains the separate source-page and learner-check counts.
- Expanding the blocked chapter and its reasons exposes a source action. It opens PDF page 2 and expands the affected topic; new teaching remains disabled.
- Opening the two saved lesson rows restores their original result and unsent practice draft/hint.
- After navigation and quit, the entire persisted `learning.json` (both sessions and map) equals its pre-navigation snapshot.

Native inspection also found that placing the fixture’s development notice above the nested split view obscured its course heading through the system scroll-edge effect. The notice is now a footer, and the rebuilt native copy shows the full heading and sidebar. This changes only the Debug fixture, not the product’s learning content. Its four isolation/restart regressions pass on the final source (`/tmp/cauchy-course-footer-fixture-tests.xcresult`).

The screen capture service initially returned ScreenCaptureKit -3811; observing the same live app recovered. VoiceOver speech, alternate appearances and system accessibility preference variants were not exercised. Unresolved-page retry placement is inspected in code; this fixture has no unresolved inventory pages. No live tutor calls were made.

## Focused questions and contextual help (JERRY-64)

Practice and exit questions now disclose the repeated learning goal. The goal still appears when introducing an idea. Generic coaching paragraphs no longer follow every teaching step or example. Worked examples retain their explicit teaching part and full-lesson location. Practice help has one disclosure beside the question, with a visible **1 hint used** / **Worked solution viewed** status when applicable. Opening it does not call the reveal-hint or reveal-solution actions. Short hint content explicitly fills the available width with leading alignment; the native check caught and corrected SwiftUI’s otherwise centered placement.

Feedback identifies **Tutor feedback** beside its grade. The existing uncertain result, reasoning criteria and practice gates remain unchanged. Completed sessions omit the inactive phase strip. Delayed checks keep their own heading and place timing/evidence context in **Check details**; they do not show the ordinary lesson’s Start/Study/Practise/Check strip. Outside-help reporting stays beside submission.

The isolated snapshot passes the four fixture regressions (`/tmp/cauchy-lesson-polish-tests.xcresult`) and **44 targeted tests, zero failures or skips**, covering learning flow, validation, workspace persistence and chapter challenges (`/tmp/cauchy-lesson-flow-tests.xcresult`). The final leading-alignment adjustment then built successfully (`/tmp/cauchy-lesson-alignment-build.log`) and was inspected natively. No test was added that merely mirrors the view layout.

Native checks on the final source, in the same 1,000-point dark window:

- The saved practice draft reopens with the help disclosure collapsed and **1 hint used** visible. Expanding shows the saved hint in alignment with the question. The entire persisted learning state remains equal to the pre-navigation snapshot after expanding/collapsing help and restarting.
- Command-Return submits to the offline tutor. Partial feedback offers revision rather than an exit check. Revealing the worked solution, collapsing help and revising retain the original draft and **Worked solution viewed** marker; no new independent evidence appears.
- Review the idea opens teaching. Command-Return reaches its explicit worked-example part, without a generic trailing paragraph. Quit and cold restart restore that exact part.
- The course’s Command-Return action opens the fresh delayed check, with its context disclosure and outside-help checkbox. Its unsent draft restores after another cold restart, with the same question and session. The full persisted learning state is equal before and after that restart.

The test app launch had one automatic approval-review timeout; the permitted single retry succeeded. Some accessibility indices changed after solution reveal; a fresh full accessibility tree and screenshot established the actual state before continuing. No source or learning-credit implementation changed. Alternate appearance and accessibility preferences, VoiceOver speech, long real-model teaching and live grading remain outside this pass’s verification.

Screenshots of the running authored fixture are retained in the chat’s artifact directory as `learn_path_polish.png` and `learn_delayed_check_polish.png`. They demonstrate production view layout on fixture data, not live mathematics or learning outcomes. JERRY-62 (contextual lesson questions) and JERRY-63 (bounded study sessions) remain planned feature work in Linear.
