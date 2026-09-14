# iCloud settings and credential sync repair

The previous service synchronized only URLs and two Unraid preferences through iCloud key-value storage. API keys were deliberately excluded, and Sync Now could report success without a confirmed cloud transaction. That left Apple TV without the credentials needed to connect.

The replacement uses the existing `iCloud.myandroidremote.ssh` container's private database. One `MediaManagerSettingsV1/settings-v1` record stores a versioned payload exclusively through `CKRecord.encryptedValues["encryptedPayload"]`. Each server URL and API key is merged as one group. TMDB credentials and the existing Unraid preferences are included. Device credentials remain in Keychain; only fingerprints and revision metadata are saved to UserDefaults.

Sync reads before writing, retries record conflicts, preserves edits made during a request, propagates explicit deletions, and rejects incomplete server groups or unsupported payload versions. An unavailable Keychain aborts sync instead of publishing empty keys. Account changes disable sync until it is explicitly enabled again. Settings refresh only when values change. Foreground startup and a 60-second active-app poll fetch remote changes; local credential/settings edits trigger a debounced request. Sync Now reports success only after a completed cloud operation and local application.

## Cloud configuration

Created `MediaManagerSettingsV1` with `encryptedPayload` of type **Encrypted Bytes** in Development and deployed to Production through the CloudKit Console. The reviewed deployment diff added only this record type and its default role grants; existing SSH record types were unchanged. The console confirmed “Changes Deployed — The schema is deployed to Production.” Runtime access is private-database only; public database security roles do not expose private records.

Apple documentation: [encrypted record fields](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues), [tvOS Keychain synchronization limitation](https://developer.apple.com/documentation/security/ksecattrsynchronizable). This implementation does not claim that enabling CloudKit is equivalent to enabling Advanced Data Protection.

## Verification and rollout

Regression tests use isolated cloud transports and synthetic credentials, including signed simulator Keychain access. Coverage includes fresh TV import, encrypted-field publishing, network errors, credential edits/deletions, edits during fetch, conflict retries, disabling during a request, account changes, newer payload versions, and malformed server groups. Final signed simulator runs passed **45 tests on iOS and 45 tests on tvOS**, including 11 new sync regressions. Matching iOS/tvOS entitlements and whitespace checks also verified. Logs: `/tmp/media-cloud-sync-final-ios.log` and `/tmp/media-cloud-sync-final-tv.log`.

These changes are local and are not in the previously uploaded 2.11 (15) build. Both iOS and tvOS need new builds for the encrypted sync protocol. Older builds continue using key-value storage and cannot exchange the new encrypted payload. Enable iCloud sync on both updated devices using the same iCloud account, then run Sync Now on the configured iPhone first and Apple TV second. Actual signed-in physical-device transfer has not been verified in this session.

## Subsequent release

The fix was subsequently uploaded for both iOS and tvOS as **2.12 (16)**. Processing completed, Internal Friends is Testing, and External Friends is Waiting for Review. See [the release report](testflight-2.12-16.md). Physical-device sync verification remains pending.
