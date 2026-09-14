# Unraid API integration review

Reviewed September 14, 2026 for Unraid 7.3.0 and newer against the official API schema and Docker resolver.

## Commands

The client posts JSON to `/graphql` with `x-api-key`. IDs are opaque: preserve the exact returned `id`, including prefixes and punctuation, in GraphQL variables.

```graphql
mutation RestartContainer($id: PrefixedID!) {
  docker {
    result: restart(id: $id) { id state status }
  }
}
```

Start and stop use the same structure with `start` or `stop`. Native restart was added in API 4.36.0; OS version alone does not determine API capabilities because the Connect plugin can supply newer API releases. If the server explicitly rejects the missing restart field during schema validation, the client awaits stop and then start. Other errors never trigger a second restart attempt.

VM actions use `vm { result: start(id: $id) }`, with `stop`, `forceStop`, `reboot`, `pause`, or `resume` as appropriate. The Boolean result must be true. The UI passes the returned domain ID instead of the deprecated UUID field.

## Corrections

- Removed ID filtering that discarded punctuation from prefixed IDs.
- Increased command timeouts from 15 to 120 seconds.
- Invalidated cached status both before and after commands, including failures.
- Preserved GraphQL error messages for HTTP 400 validation responses and partial data.
- Rejected missing command results and false VM results.
- Displayed Docker command errors to users and ignored repeated taps during an operation.
- Clarified that viewer access is sufficient for monitoring, but controls need update permission.

A client timeout does not establish whether a command completed on the server. No automatic retry follows a timeout. The stop/start compatibility fallback can leave a container stopped if the subsequent start fails; the error explains that outcome.

## Sources

- [Official API availability](https://docs.unraid.net/API/)
- [Official schema](https://github.com/unraid/api/blob/main/api/generated-schema.graphql)
- [Docker mutations and permissions](https://github.com/unraid/api/blob/main/api/src/unraid-api/graph/resolvers/docker/docker.mutations.resolver.ts)
- [API 4.36.0 release](https://github.com/unraid/api/releases/tag/v4.36.0)

Mock HTTP regression coverage exercises native restart, exact ID preservation, missing-field compatibility fallback, authorization/errors without retries, missing results, partial errors, and false VM responses. This does not verify a restart against a live Unraid server.

## Full integration and performance review

The second pass covered the service, response models, server screen, dashboard health card, Docker/VM cards, connection settings, Siri status intent, and Unraid participation in backup/cloud settings flows.

### Additional changes implemented

| Area | Finding and correction |
| --- | --- |
| Cache correctness | The five-second cache was global to the service and configuration invalidation was asynchronous. Cache and in-flight task selection are now atomic and keyed to the exact endpoint/key. Results from superseded credentials are rejected. Explicit refresh bypasses completed cached results while still sharing an in-flight read. |
| Command routing | A stop/start fallback could read newly changed settings between steps. The complete restart sequence now retains its original endpoint/key. VM requests also capture credentials before awaiting cache invalidation. |
| Schema compatibility | Disk name/size/status and VM name/UUID can be null. Models accept the nullable fields; VM queries now use ID and omit deprecated UUID. Memory BigInt fields accept numeric and string representations. Boot disks are no longer classified as data disks. Storage conversion/summation cannot overflow. |
| Request size and maintenance | Centralized repeated field selections and system mapping. Removed unused online, disk-count, fsFree, and deprecated UUID selections. Removed the unreachable Docker fallback that could not run after the transport threw a GraphQL error. |
| UI command state | Removed fixed two-second busy timers. Start, stop, and restart remain busy until completion; repeated commands are ignored in the same screen. VM errors now appear alongside Docker errors. Paused resources use unpause/resume instead of start. Navigation away does not cancel an issued command midway through stop/start. App termination or suspension can still interrupt network work. |
| Freshness | Failed refreshes show a warning with retained data, instead of silently appearing current. Server-screen publication uses generation checks. Credential changes restart loading. |
| Dashboard lifecycle | One lifecycle-bound task performs initial load/retries and periodic refresh; polling pauses while inactive/hidden. Nontransient initial errors do not use the network retry loop. The status label identifies array state rather than calling a stopped array an offline server. |
| Metrics | CPU utilization is now displayed, not only core count. Missing CPU/RAM metrics are labelled unavailable in the card and Siri. Percentages are bounded. |
| Settings and transport | Accepts a base URL or `/graphql` endpoint without duplicating the path. Rejects invalid schemes and URL credentials/query/fragment. Settings save errors are surfaced on explicit back/save. Requests bypass URLSession response caching and cookies; API-key permissions are authoritative. HTTP 403 is distinguished from an invalid key. Response payloads are no longer dumped on decode failures. |

Backup and cloud settings already include Unraid credentials/preferences and apply credentials before publishing URL changes. No backup-format or encryption change was needed. The new request identity protects reads after those flows refresh configuration as well.

### Recommended next changes, in priority order

1. **Separate summary and detail reads, with per-section availability.** The dashboard and Siri still fetch full disk and VM details they do not display. Use a compact shared summary for them; fetch detailed disks/VMs on the server screen. Keep healthy sections visible when a single resolver fails. Display unavailable distinctly from an empty container/VM list. This is the strongest remaining performance/resilience improvement.
2. **Discover and cache capabilities and permissions per endpoint/key.** Determine supported fields/actions at connection time and retain API version separately from OS version. Explain disabled controls, surface denied read resources, and remember missing native restart support instead of sending the same rejected command on every restart. Keep an option to refresh capabilities after an API upgrade.
3. **Use different refresh intervals for different data.** Hostname, version, CPU model, and disk inventory rarely change; CPU/RAM/container state change more often. Retain slow data longer. Add measured backoff/Retry-After handling for background polling. Evaluate foreground GraphQL subscriptions with reconnect/polling fallback only after measuring their benefit; do not introduce an always-on background socket.
4. **Improve operational diagnostics.** Add capability-gated container logs, resource metrics, and a direct WebUI link. Add parity-check status and boot-device/pool awareness where available. These help distinguish an API permission failure from a container that starts and immediately exits. Prefer read-only diagnostics before expanding destructive controls.
5. **Finish lifecycle and command verification.** Move resource command coordination into the service if multiple server screens can operate simultaneously. Poll for expected state for asynchronous VM shutdown/reboot, with a bounded deadline and honest pending/error display. Add simulator UI coverage for slow commands, navigation, foreground return, and server/key changes; run the same checks against an actual 7.3.x server.

No latency, battery, or live-server performance improvement is claimed from builds or mock tests. The present tests establish request counts, parsing, routing and error behaviour; profiling and physical-server checks remain necessary to quantify runtime gains.

### Verification completed

- Four Unraid regression tests passed on the iOS 27 iPhone 17 simulator: command/fallback failures, nullable snapshots and cache identity, endpoint/retry/overflow handling, and missing metrics.
- The cache test confirms two concurrent callers share one HTTP request, a subsequent read reuses it, force refresh makes another request, and key/server changes each trigger a new authenticated request.
- All 15 read/mutation shapes validated against both the official API v4.36.0 schema and the fetched current main schema. This checks GraphQL shape, not runtime authorization, feature flags, or daemon behaviour.
- Final iOS and tvOS simulator builds passed, and `git diff --check` passed.
- Live Docker/VM execution, physical-device foreground/background behaviour, and latency/battery measurements remain unverified. No server commands or deployment were performed during this audit.
