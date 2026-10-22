# Native export readiness — 22 October 2026

[JERRY-106](https://linear.app/jerryjin/issue/JERRY-106) investigates a standard save sheet that sometimes leaves Export disabled despite a valid Markdown name and temporary destination. Actual files now verify ordinary selected work, personally set-aside work and full history on the unchanged `3313659` implementation. The user subsequently confirmed Export was enabled after manually foregrounding the post-restart panel. Automation still cannot operate that panel reliably; readiness remains unresolved. No speculative application fix has been made.

## Verified files and state

The running disposable `/tmp/CauchyLearnSearch84.app` (`com.cauchy.learn-search84`) retains debug dylib SHA-256 `1491a0008a1cb9ab9d3a24498a4ff110cef6ce460c165dff12f0ba9a4c51a0eb`, the final 414-test assessment-review build. Its authored root is `/tmp/cauchy-ui-fixture-assessment105-native`.

| Actual native output | Scope | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `/tmp/cauchy-export106-selected.md` | One original ordinary record | 1,648 | `3d1de16224c8996b8af79cf925750e69613f4a1aee7d937abaf8d3fd6663044c` |
| `/tmp/cauchy-export106-set-aside.md` | One personally set-aside record | 1,801 | `8e660c295fb0c4f08ccdcd3d0c5365e567aa5575c93ef1b56555f70a5926a8f0` |
| `/tmp/cauchy-export106-history.md` | Two requirement records | 4,880 | `65896aed76f05ff2d162dd88080225b61375a7df5d3b5b658a561ba86e0efe30` |

Each file was saved through the real native Export button. The first selected file retained the ordinary result before the fixture was extended. Then an offline authored question and unsubmitted draft were deliberately created, and the earlier result was personally set aside. The qualified selected file contains only that original answer/feedback and original Correct grade beside its dated exclusion. The full file retains both records in recent-first order, including the complete actual 2,375-character draft as exact line-preserving block quotes, through its marker and trailing text. Hidden answer keys/hints, raw source pages and the unrelated closed-subset draft are absent. This is authored engineering data; no assessment or live provider call occurred.

Each save visibly returned to the same selected history record. A separately named cancelled export returned without creating `/tmp/cauchy-export106-cancel.md`. Exporting/cancelling left the entire learning sidecar equal to `/tmp/cauchy-export106-qualified-before.json`, taken after the deliberate fixture changes. Quitting, confirming the process had stopped and cold restarting preserved that complete state and all three file hashes. History restored the exact draft and the personal qualification. The first ordinary export also matched its earlier two-session baseline `/tmp/cauchy-export106-before.json`.

These observations extend [assessment-review verification](learning-assessment-review.md#export-observation-and-limits) with actual qualified file output. They do not establish that every subsequent save panel is ready.

## Readiness observations

Opening the disposable application using Finder's exposed Open action enabled a selected-record save on the unchanged binary. Later, another already-open panel changed from disabled Export to enabled Export after the same normal app-opening action, without changing its filename, destination or code. Both qualified/full exports then succeeded using the same action before saving.

However, after the cold restart, another same-panel comparison remained disabled both before and after that action. The filename and temporary destination were unchanged. The captured comparison is `/tmp/cauchy-export106-activation-control.json`; screenshots are `/tmp/cauchy-export106-before-activation.png` and `/tmp/cauchy-export106-after-activation.png`. Accordingly app activation is a plausible influence, not an established complete explanation or reliable workaround. Native coordinate clicking previously reported `noWindowsAvailable`, and keyboard edits in the panel have behaved inconsistently.

A non-UI Swift diagnostic confirms the current Markdown type is `net.daringfireball.markdown`, declared, non-dynamic, conforming to plain text, with preferred extension `md`. The project has app sandboxing disabled. These checks identify the current configuration, without proving the save service's readiness or focus state.

## Manual foreground check and identity control

The user brought CauchyLearnSearch84 and its existing Export learning work panel forward and reported **Export is enabled**. A subsequent screenshot agrees (`/tmp/cauchy-export106-manual-enabled.png`): the selected-work panel shows the temporary destination and enabled Export. In that observation, the accessibility tree contains only the sheet and app menus, omitting its filename, destination and buttons. A coordinate click grounded in that screenshot fails with `noWindowsAvailable` before the filename can be changed. Consequently `/tmp/cauchy-export106-restart.md` remains absent; no post-restart file save is claimed. The complete learning sidecar still equals the qualified baseline, and all three previously saved files retain the hashes above. The primary panel is left open.

Two control bundles isolate additional variables:

- `/tmp/CauchyExportIdentity106.app` copies the same current debug dylib byte-for-byte, with a unique aligned executable, bundle name and display name, a separate bundle ID and fresh authored fixture root. It was launched and navigated through the actual application requirement history into Save selected record. The fresh native panel defaults to Documents and its generated record name, with Export disabled in both accessibility and screenshot observations. A grounded coordinate click fails with the same `noWindowsAvailable` error. Cancel returns to the original selected history record. Thus aligned unique app naming alone does not resolve the observed automation failure; this does not isolate activation, destination or save-service state. The primary copy's display name/executable remain `cauchy`/`Cauchy` while its bundle name is CauchyLearnSearch84.
- `/tmp/CauchyExportControl106.app` builds pinned pre-assessment-review checkpoint `fc535f0` from `/tmp/cauchy-export106-control-source` into a separate derived-data directory. Its build succeeds (`/tmp/cauchy-export106-control-build.log`), with SwiftMath still pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`. Its debug dylib SHA-256 is `4adb9121e8337f0ef516a3828d446cf415340bb2de1fe51c7eb226ae26a7b592`. It also uses a unique identity and fresh fixture root, so it is an isolation control rather than a claim that only one runtime variable differs. This older-code control has not been launched.

Both controls are isolated from the normal library and the current authored root. Repository app code is unchanged from the 414-test checkpoint; the suite was not repeated for this diagnostic/evidence work. The installed app, normal learner library and system settings remain unchanged. JERRY-106 stays In Progress. Manual readiness is useful evidence, but cannot substitute for a new saved file or establish the root cause. Write-error fault injection, complete keyboard/accessibility coverage and educational/model-quality claims remain outside these observations.
