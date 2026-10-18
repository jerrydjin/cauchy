# Chapter availability and source recovery — 17 October 2026

`LearningStudyMap.chapterAvailability` derives eligibility and specific blockers from the current inventory. It reports missing connections/topics, damaged extraction, missing usable proof arguments, each unresolved source warning (including explicit omissions and prerequisites), and unresolved pages used by a connected pair. It considers every in-chapter connection, so one incomplete pair does not hide another supported pair. A source-complete pair may be attempted before the learner has passed individual checks; availability describes source support, not learner readiness.

The chapter disclosure shows **Chapter challenge unavailable**, distinguishes source support from understanding, and offers a direct **Review source · PDF page …** action. The action opens the source inspector at the evidence page and expands the affected topic, preserving its warnings and proof requirements. Proof obligations are visible even when the inventory supplies no warning text. Correcting or reviewing source never creates an attempt or changes prior learning evidence.

The derived result recomputes after validated reconciliation without replacing unit IDs, original targets, course order, drafts or attempts. Source faults remain blocked; there is no override to waive a proof or prerequisite. Mathematical transcription correction is separate work under JERRY-51.

## Verification

The initial focused macOS run passed 52 cases. The later retained full regression result (`/tmp/cauchy-linear-final.xcresult`) authoritatively reports 260 passing tests and no failures, including the subsequent source-correction, delayed-review, syllabus and proof-replay checks. Three chapter-recovery regression methods cover:

* An incomplete connected pair becoming available only after source-validated review adds an unchecked proof target; unchanged original IDs/targets and serialized saved evidence; a newly unresolved cited page blocking it again.
* A second source-complete pair remaining available while the first pair is incomplete; a missing connection and a stale module remaining unavailable.
* The captured Metric Spaces audit: PDF p. 5 extraction damage and the explicitly omitted multivariable chain-rule proof remain distinct blockers with the correct topic/page and no learning credit. This uses the existing captured source review, not fabricated successful learner data.

Both test commands used `/Applications/Xcode.app/Contents/Developer` and the established `/tmp/cauchy-learning-build`. The first sandboxed run could not write Xcode's manifest/compiler caches; the approved run completed. Simulator-version warnings do not affect the macOS destination.

At that initial attempt, native interaction remained unverified. `cua.getApp` for the exact Debug bundle returned a Library accessibility tree, but the next click was rejected as **Computer Use is not active**, an explicit state refresh timed out, and bundle-ID binding was ambiguous across installed copies. No chapter interaction, visual focus, layout, or accessibility-setting behavior can be inferred from that snapshot. At that point JERRY-50 still lacked native evidence. The new isolated native verification fixture idea is tracked as JERRY-56.

A later attempt copied the tested Debug bundle to `build/verification/CauchyVerification.app`, gave it the separate `com.cauchy.verification` identifier, and ad-hoc signed that verification copy. The installed application was not replaced. Binding its exact path through `cua_repl` also failed: ScreenCaptureKit error **-3811, audio/video capture failure**. The call requested a 20-second timeout but returned after approximately 896 seconds. This is an automation/environment failure, not evidence that the product flow passed or failed. No further polling of that failed binding was used.

UI changes use the existing native disclosure/button patterns and preserve the current glass controls. References checked: [DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup) and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## 18 October follow-up

The isolated authored fixture overcame the earlier binding failure. Its [native report](learning-ui-fixture.md) records the course/chapter/refresher journey, real quit/restart with saved question/draft/help, a discovered and fixed answer-focus defect, narrow layout, blocked-chapter direct PDF/topic recovery, and transcription revalidation retaining an explicitly omitted proof. Accessibility labels and keyboard submission/return were inspected; VoiceOver speech, accessibility preference variants and nonzero visual scroll restoration remain untested. The native incomplete scenario is authored; the realistically incomplete Metric Spaces case remains covered by its captured-source regression rather than a claim of native testing on real learner notes.

The final retained full macOS result `/tmp/cauchy-learning-completion-audit.xcresult` reports 266 passing tests with no failures or skips. The earlier capture errors above are historical evidence, superseded for these specific native flows by the successful fixture observations. Local checkpoint references are recorded in [work tracking](../work-tracking.md); a checkpoint is not a published release.
