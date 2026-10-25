# Closed-note review overview profile

Tracked by [JERRY-126](https://linear.app/jerryjin/issue/JERRY-126), following the [prepared-review projection profile](learning-review-performance.md). This opt-in diagnostic measures the remaining refresh work when all notes are closed: summary discovery, actual workspace/learning-file reads and decoding, and compact schedule preparation. It then times prepared row calculation separately. It does not open PDFs, create a Learn document, call a tutor or change the persistence implementation.

## Authored inputs and reproduction

The diagnostic starts from the existing offline learning fixture and repeats its completed application session with unique saved IDs and an eligible due schedule. Each document has one eligible application target; older sessions add history volume without adding requirements. Cases contain 1 × 144, 8 × 360 and 16 × 720 saved sessions. These history-heavy cases differ from the many-target live-library cases in the earlier audit and are not a matched speedup comparison.

Each case saves normal workspace, learning-sidecar and summary files through `DocumentPersistenceService`, then creates a fresh `LearningLibraryStore` with no installed documents. Two sequential overview refreshes use the actual closed-workspace load path. PDF URLs are authored but no PDF files are written or opened. Fixture construction and saves are outside the timed interval. The first refresh follows writing and reading the input files: **it is not an OS cold-cache measurement**. No cache purge or system-setting change is used.

```sh
python3 scripts/profile_learning_reviews.py \
  --mode closed \
  --output /tmp/cauchy-closed-review-profile-new \
  --package-cache /path/to/existing/SourcePackages \
  --revision fec5507
```

Use Python 3.12 or newer, `/Applications/Xcode.app` and an existing resolved package cache. Output must be a new temporary directory. `--derived-data` may select task-owned build storage. The script exports the committed revision, appends only the selected opt-in fixture and records exact source/harness hashes. The default remains `--mode live`; neither profiler fixture enters the ordinary app/test target.

## Observations — 25 October 2026

The selected diagnostic passes in the standard unoptimized Debug macOS test host, with zero failures/skips or reported runtime warnings. Sizes below count learning sidecars plus workspace files; summaries and PDFs are excluded. Refresh times combine reading, decoding and preparation rather than attributing cost to one phase.

| Closed notes | Sessions per note | Learning sidecars (MiB) | Workspaces (MiB) | First refresh (ms) | Repeat refresh (ms) | Prepared rows, first / repeat (ms) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 144 | 0.675 | 0.911 | 22.283 | 20.781 | 0.036 / 0.018 |
| 8 | 360 | 13.455 | 18.148 | 408.260 | 392.892 | 0.048 / 0.046 |
| 16 | 720 | 53.761 | 72.491 | 1,535.463 | 1,529.561 | 0.094 / 0.103 |

The largest case contains 11,520 saved sessions and about 126.252 MiB across the two file types. Its repeat refresh still takes about 1.5 seconds, while prepared rows take about 0.1 ms. The existing refresh deliberately reloads closed work; this result identifies a remaining startup/refresh cost and does not imply that the overview opens in 0.1 ms. No persistence shortcut is justified solely by these two warm-file samples.

Every refresh asserts the expected document count, exactly one due target per note, no in-progress target and no unreadable notes. It also asserts that the document collection stays empty and the destination remains unset. Every saved learning sidecar is compared byte-for-byte with its original after both refreshes. This establishes read-only learning-state behavior; it is not an audit of every base-workspace byte or memory consumption. Original sidecar data is retained in the diagnostic for that comparison.

[Structured samples and exact inputs](learning-review-closed-profile.json) record checkpoint `fec550755133191ae4d835f4c09ad76cea75b281`, no working-tree overlay, the five Learn implementation hashes and fixture hash. The isolated archive, log and passing result bundle remain at `/tmp/cauchy-review126-closed`. SwiftMath is pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`, with automatic package resolution disabled.

A separate invocation without `--mode` at `/tmp/cauchy-review126-live-control` passes the existing live diagnostic, confirming the default selection still works. It uses the unchanged live harness and verifies all three expected row/due-count cases. Python syntax/help checks and `git diff --check` pass. App and ordinary test sources are unchanged from the verified 445-test checkpoint; no additional full-suite result is claimed for this tooling-only milestone.

The measurements exclude PDF loading, native rendering, Release optimization, OS cold-cache I/O, realistic mixed learner libraries and arbitrary concurrent file changes. The earlier native navigation/restart evidence applies to the product checkpoint, not this larger diagnostic. Reader/persistence behavior, the normal learner library and system settings remain unchanged. No live model evaluation, push, merge or release occurred.
