# iOS and tvOS TestFlight 2.12 (16)

Release prepared September 7, 2026 for Dragon Media Manager, App Store Connect ID `6757086853`.

## Validation

- Final sync code passed 45 signed simulator tests on iOS and 45 on tvOS, including 11 new sync regressions.
- Version/build updated to 2.12 (16) in all 10 app, widget, and Watch Xcode build configurations. Settings derives its display from the installed bundle.
- Both Release archives built successfully, and deep/strict code signature verification passed.
- Main app, iOS widget, and embedded Watch app bundle versions verified as 2.12 (16).
- Release executables contain the encrypted sync implementation. TV offline design fixtures are excluded.
- Distribution signing logs confirm `com.apple.developer.icloud-container-environment = Production` on both platforms.
- Production CloudKit Console directly verified `MediaManagerSettingsV1.encryptedPayload` as **Encrypted Bytes** in `iCloud.myandroidremote.ssh`.
- Physical iPhone-to-Apple-TV transfer with a signed-in iCloud account remains a tester validation step.

## Artifacts

Archives are in `/Users/jamesmaine/Library/Developer/Xcode/Archives/2026-09-07/`:

- `Dragon Media Manager iOS 2.12 (16).xcarchive`
- `Dragon Media Manager tvOS 2.12 (16).xcarchive`

Archive/upload logs: `/tmp/media-ios-212-archive.log`, `/tmp/media-tvos-212-archive.log`, `/tmp/media-ios-212-upload.log`, `/tmp/media-tvos-212-upload.log`.

No Git commit or push was made as part of this release.

## Tester instructions

Update both iPhone and Apple TV to 2.12 (16). Sign in to the same iCloud account and enable iCloud Sync in both apps. On the configured iPhone, tap Sync Now and wait for success; then tap Sync Now on Apple TV. Verify the servers connect without re-entering keys, then test credential edits and configuration removal. Older app versions cannot exchange the new encrypted payload.

## Upload

Both uploads completed successfully. tvOS: 21:14 EDT; iOS: 21:15 EDT. Both upload logs report `Upload succeeded` and `EXPORT SUCCEEDED`. App Store Connect lists 2.12 (16) for each platform.

## Final App Store Connect status

Verified after processing and tester assignment:

| Platform | Latest build | Internal Friends | External Friends |
| --- | --- | --- | --- |
| iOS | 2.12 (16) | Testing, 1 tester | Waiting for Review, 4 testers |
| tvOS | 2.12 (16) | Testing, 1 tester | Waiting for Review, 4 testers |

English (Canada) test notes saved for both builds. Automatic external tester notification is enabled after Apple approves beta review. Previous builds remain available; these are the newest versions on both platforms.

- [iOS build](https://appstoreconnect.apple.com/teams/be15dce6-bd72-4949-9448-8c1f5b2fe0df/apps/6757086853/testflight/ios/bdfebe6b-a283-4a80-8344-398c897789de)
- [tvOS build](https://appstoreconnect.apple.com/teams/be15dce6-bd72-4949-9448-8c1f5b2fe0df/apps/6757086853/testflight/tvos/35ab65a7-f598-4697-a172-19176dd8dcea)
