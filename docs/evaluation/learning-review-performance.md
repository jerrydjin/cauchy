# Review overview projection performance

Tracked by [JERRY-125](https://linear.app/jerryjin/issue/JERRY-125). This audit profiles the synchronous projection behind **Review across notes**, introduced in [the multi-document review flow](learning-review-overview.md). It uses only generated authored work in an isolated test host. It does not read a normal learner library, open PDF windows, call a tutor or make a learning-efficacy claim.

The opt-in harness constructs three scales: 1 document with 12 topics/144 saved sessions; 12 documents with 40 topics/720 saved sessions each; and 30 documents with 80 topics/1,920 saved sessions each. Every topic has concept, proof and application requirements. Histories contain repeated independently correct checks with an eligible due schedule. Every measured projection must return exactly the expected document and due-check counts. Three monotonic-clock samples are collected per case; no brittle timing threshold enters the ordinary test suite.

The profile uses the project’s standard unoptimized Debug test host. Optimized-host attempts failed before executing any profile because the test bundle could not be loaded; they establish no optimized timing result. It records overview preparation separately, then measures live-library row projection, excluding fixture setup, PDF loading, closed-history decoding and view drawing. These observations therefore address synchronous row computation, not complete overview startup or general application responsiveness.

## Reproduction

From the repository, with Python 3.12 or newer, Xcode installed at `/Applications/Xcode.app` and an existing resolved package cache:

```sh
python3 scripts/profile_learning_reviews.py \
  --output /tmp/cauchy-review-profile-new \
  --package-cache /path/to/existing/SourcePackages \
  --revision 31a62d0
```

The output directory must be new and inside temporary storage. The script exports the requested committed revision, extracts the pinned SwiftMath source, appends the opt-in fixture to the existing isolated test target and runs only that diagnostic. It records source/harness hashes, the result bundle, build log and structured samples. `--derived-data` can reuse task-owned build storage. `--working-tree` explicitly overlays only the declared Learn implementation files, allowing the same harness to compare an uncommitted candidate with its committed baseline. No repository branch or index is changed.

## Findings and change — 25 October 2026

The baseline rescanned every document session for every requirement, then repeated the full scan while checking its independent evidence. A first candidate grouped histories by target ID and kept the full unit/kind/objective/revision matching inside each group. This reduced the largest Debug projection from about 30 seconds to about 0.8 seconds, but repeating that work in a view was still too expensive.

The final change retains that grouping and prepares a small `LearningReviewSchedule` per document. It holds eligible scheduled dates and in-progress dates, sharing the exact candidate selector used by the actual review queue. Future checks remain in the schedule; a binary search calculates the due prefix at the current clock. Moving the clock backward or forward does not require rescanning answers and cannot create evidence.

Closed-note schedules replace cached full histories. Live schedules are keyed to ephemeral session/map revisions, including direct restore and nested model changes. Cache hits still read the observable revisions so subsequent updates invalidate the view. The memoized values themselves are excluded from observation, avoiding a derived cache write becoming a view-state publication. These revisions and schedules are never persisted and never replace an assessment.

On refresh, preparation runs in detached utility tasks over immutable Sendable snapshots. A live result is adopted only if its captured revisions still match; request/cancellation guards reject an obsolete refresh. Already-current live schedules are reused. Initial sheet content shows preparation before asking for rows, so it does not demand a cold scan during the first body evaluation. If live work changes later, only the invalidated document requires a fresh schedule; its current result remains authoritative immediately.

The final profile measures preparation separately from three subsequent row projections. Medians below come from the same harness and equivalent authored cases. Baseline preparation took 0.35–4.50 ms because it deferred live-history evaluation to row projection; that deferred cost is included in the baseline row column.

| Documents | Saved sessions per document | Baseline row median (ms) | Candidate initial preparation (ms) | Candidate prepared row median (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 144 | 12.984 | 2.996 | 0.007 |
| 12 | 720 | 2,204.338 | 129.216 | 0.058 |
| 30 | 1,920 | 28,643.600 | 784.487 | 0.184 |

The candidate moves work into preparation; the table is not a claim that the complete overview opens in 0.184 ms. Initial preparation is roughly 0.8 seconds in the largest authored live-library case and runs away from the main actor. A later invalidated live document can still require recomputation. No Release timing or closed-library decoding/startup profile is established here.

[Structured samples and exact input hashes](learning-review-profile.json) retain all three samples per case. The matched baseline is `/tmp/cauchy-review125-matched-baseline`; the final candidate is `/tmp/cauchy-review125-final-profile`. Their `profile-inputs.json` files identify the same base commit `31a62d0` and identical harness hash; the candidate overlays the five declared implementation files. Both selected diagnostics pass and verify every expected row and due-check count. The earlier grouped-only result and unsuccessful optimized-host attempts remain separately retained. Neither optimized-host attempt executed the profile; both failed at test-bundle loading with a signing/Team-ID mismatch. The successful measurements use the project's ordinary Debug configuration without signing or system-setting changes.

## Correctness and verification limits

The final complete normal macOS suite passes **445 tests, zero failures/skips and no reported runtime warnings**. The opt-in timing test is not compiled into this ordinary target. Three added regressions establish:

* histories sharing a target ID still require exact unit, kind, objective and revision identity; unrelated/unbound sessions do not affect selection, course context alone preserves a requirement, assisted latest work stays ineligible, and a valid active draft remains inspectable when source review is required;
* the compact schedule agrees with the current queue across due boundaries and a backward clock change, preserves future checks and active work, and handles empty schedules;
* repeated prepared reads do not mutate learning revisions, direct in-memory restoration invalidates a cached result without relying on a save callback, map/source assignment and nested reconciliation changes invalidate it too, and cache hits retain actual Observation dependencies for both kinds of change.

The correctness archive `/tmp/cauchy-review125-validation` uses `31a62d0` plus seven exact source/test inputs recorded in `/tmp/cauchy-review125-inputs.json`. SwiftMath is pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`; package resolution remains disabled against the existing cache. Results: `/tmp/cauchy-review125-verified.xcresult`, `/tmp/cauchy-review125-verified.log`, `/tmp/cauchy-review125-verified-summary.json`. The earlier full suite also passed before the additional Observation assertions. No new application or ordinary-test Swift files require project regeneration; the profiler fixture lives outside those source roots.

Native verification of this checkpoint is **pending**. The computer-use tool twice reported the Mac locked and automatic unlock failed; a manual unlock was requested. No prepared-app window could be observed. A separate authored three-record library remains ready at `/tmp/cauchy-ui-fixture-review125-native`, and the exact 445-test dylib is pinned at `/tmp/cauchy-review125-final-tested.dylib` (SHA-256 `09a6d9824d7c3d49f9c7853c3836e5d4676b7ad6d662e370a39787898caa5e88`). The disposable app was confirmed stopped, and its earlier plist/dylib have been restored byte-for-byte. Prepared learning state is unchanged. The preceding native evidence for JERRY-119 does not substitute for observing this checkpoint's preparation/cache flow.

These results establish the stated Debug timing and automated behavior. Native preparation/refresh, navigation, restart and unchanged-record checks remain required for this follow-up. General learning efficacy, mathematical accuracy, native accessibility, Release performance, real large-library disk startup and exhaustive concurrent-refresh orderings remain unproven. The installed app, normal learner library, reader and system settings are unchanged. No live model evaluation, push, merge or release occurred.
