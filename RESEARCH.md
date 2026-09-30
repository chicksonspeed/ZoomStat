# ZoomStat — Phase 1 research report

Machine: MacBook Pro (arm64, 11 cores, 36 GB), macOS 15.7.7
Zoom: Zoom Workplace 6.5.7 (60598), Team ID BJ4HAAB9B3, hardened runtime
Date: 2026-09-30 / 10-01, performed during a live meeting (wired network, AMS data center, camera on, mic muted, not sharing)

## TL;DR

The Zoom Statistics panel (Settings → Statistics) is fully exposed through the
macOS Accessibility API. Every value in the Overall, Audio, Video and Screen
sharing tabs is readable as plain text, it keeps updating about once per second
**while the Settings window is minimized**, and the tabs can be switched with
`AXPress` while minimized — nothing flickers on screen. No other local source
exposes the media statistics (latency, jitter, loss, resolution, FPS).

Recommended source: **Accessibility (AX) reading of the Statistics window**,
isolated behind `AccessibilityZoomStatsProvider` + a version/locale adapter,
merged with **native system metrics** (CPU, memory, network type, proxy,
version) that work even when the Statistics window is closed.

## Zoom process map (in meeting)

| PID  | Process | Role |
|------|---------|------|
| 41815 | `zoom.us.app/Contents/MacOS/zoom.us` | Main client: UI, meeting, media engine (all media sockets live here) |
| 41828 | `Frameworks/caphost.app` (`-pid 41815 -key rpc`) | Helper, RPC with main process (capture/annotation host) |
| 92962 | `Frameworks/CptHost.app` (`-pid 41815`) | Capture host; owns 64 MB POSIX shm `cpthostfm<pid>` (frame buffer) |
| 398 | `ZoomAudioDevice.driver` (Core Audio) | Virtual audio device for share-audio |
| — | `us.zoom.ZoomDaemon` (LaunchServices) | Privileged installer/updater helper, not running during meeting |

Relevant frameworks/bundles: `zVideoApp.bundle`, `zVideoUI.bundle`
(contains `ZMNotificationCenter statisticWarningReceived`), `zConfUniversalUI`,
`zNet.bundle`, `zNetDiagnostic.framework`, `ZoomTelemetry.bundle`,
`zEventTracker.framework`, `ZMDB.framework`, `viper.framework`.
No XPC services are bundled.

## Sources investigated

| # | Source | Finding | Usable? |
|---|--------|---------|---------|
| 1 | Logs `~/Library/Logs/zoom.us/zoom_ts_memlog_*.log` | Plain text, written live, but messages are hashed IDs (`#2FTM1gGaz4t#…`). 0 hits for jitter/latency/loss/bitrate/resolution. Only URLs and opaque tokens. `zoom_feedback/*.zenc` encrypted. `net_records/` empty. | No |
| 2 | Prefs `us.zoom.xos`, `viper.ini` | UI state only, no stats | No |
| 3 | SQLite DBs in `~/Library/Application Support/zoom.us/data` | `zoomus.enc.db`, `zoommeeting.enc.db`, `eventdata.db`, … — all headers are ciphertext (SQLCipher), not `SQLite format 3` | No |
| 4 | Caches (`confres`, `ConfAvatar`) | Images/avatars only (also privacy-sensitive) | No |
| 5 | Unix sockets | `/tmp/zeb_def_ipc_<pid>`, `…/BJ4HAAB9B3.ZoomClient3rd/s.zoomclient`, `s.zzhost` — undocumented private IPC for 3rd-party integrations/helpers. Talking to them risks interfering with the client. | No (unsafe) |
| 6 | Local sockets | Media over UDP `→ <zoom MMR>:8801` (5 flows), signalling TCP 443. No listening ports. | Partial (connection type only; not needed) |
| 7 | XPC | None bundled | No |
| 8 | IPC between processes | caphost/CptHost RPC keyed per launch; private | No |
| 9 | localhost endpoints | None listening | No |
| 10 | Shared memory | `/aomshm.*` (4 MB) and `cpthostfm<pid>` (64 MB) — frame/annotation buffers, not statistics | No |
| 11 | Process env/state | `proc_pid_rusage`, `nettop` give CPU, memory footprint, byte counters | Yes (system metrics) |
| 12 | Frameworks/helpers | Stats computed inside the media engine in `zoom.us`; only surfaced through the UI (`statisticWarningReceived`) | Via UI only |
| 13 | Process memory | Hardened runtime, no `get-task-allow`; `task_for_pid` needs root + SIP changes. Also forbidden by the project rules. | No |
| — | **Accessibility API** | Full Statistics panel as text (below) | **Yes — primary** |

## Accessibility structure (Zoom 6.5.7)

```
AXWindow "Settings"
  AXSplitGroup
    AXScrollArea > AXTable desc="Category List"
      AXRow > AXCell desc="Statistics, Selected"      ← AXSelected=true selects it
    AXScrollArea desc="Statistics settings"
      AXScrollArea > Tab title="Overall, Selected" | "Audio" | "Video" | "Screen sharing"   (AXPress)
      AXScrollArea > AXStaticText/AXGroup (values in AXDescription)
```

Values are leaf `AXStaticText` elements whose `AXDescription` holds the text.
Some rows are wrapped in an `AXGroup` (whose description concatenates the row),
others are flat siblings — the parser flattens leaves in document order and is
label-driven, so it handles both.

Captured values (Overall): `CPU  Zoom 7%  Overall 88% (Medium)`, `2.4GHz Cores: 11`,
`Memory Zoom 1.91 GB  Overall 28.83 GB (High)  36.00 GB`,
`Bandwidth: 838 kb/s (send) 1930 kb/s (receive)`, `Network type: Wired`,
`Proxy: --`, `Connection type: Cloud`,
`Data Center: You are connected to Zoom Global Network via data centers in the Netherlands (AMS)`,
`Encryption: AES-256-GCM`, `Version 6.5.7 (60598)`.

Audio: `Frequency -- / 48 KHz`, `Latency -- / 26 ms`, `Jitter -- / 2 ms`,
`Packet loss - average(max) -- / 0.0% (0.0%)` (send is `--` because the mic was muted).

Video: `Latency 28 ms / 26 ms`, `Jitter 2 ms / 0 ms`, `Packet loss 0.0% (0.0%) / 0.0% (0.0%)`,
`Resolution 640x360 / 640x360`, `Frames per second 26 fps / 25 fps`.

Screen sharing: same rows as Video, all `--` when nobody shares.

Raw dumps: `research/fixtures/ax_*.txt` (used as parser test fixtures).

## Experiments

| Experiment | Tool | Result |
|---|---|---|
| Grep live log for stat keywords | `grep -c` | 0 matches for media stats |
| DB header check | `xxd` | all encrypted |
| Socket/port inventory | `lsof -p`, `lsof -iTCP -sTCP:LISTEN` | private IPC only, no listeners |
| Per-process traffic | `nettop -P -L1 -p` | cumulative bytes available (not used) |
| AX trust from CLI | `research/axdump` | `AXIsProcessTrusted: true` |
| Select Statistics category | `research/axselect` | `AXSelected` on row works |
| Switch tabs | `research/axpress` | `AXPress` on `Tab` works |
| Live update | 3 samples, 1 s apart | bandwidth/CPU change each sample |
| **Minimized window** | `research/axmin 1` then read | values keep updating; tab switching still works |
| Read immediately after tab switch | — | first ~300 ms returns labels without values → provider waits before reading |
| Compare with panel | side by side | identical text (it *is* the panel) |
| Minimize later in session | `research/axmin 1` | returned success but the window stayed un-minimized (Settings had moved to a second display while the meeting was full-screen) → rotation must not depend on minimizing; it now pauses only while the user is focused on the Settings window |
| Rotation timing | `ZOOMSTAT_DEBUG=1` | at 1 s per tab every tab parsed on first read; full cycle ≈ 4 s |

## Statistics obtained

All target statistics are obtainable from AX while in a meeting:
Zoom/overall CPU, Zoom/overall memory, bandwidth send/receive, network type,
proxy, connection type, data center, encryption, version; audio frequency,
latency, jitter, avg/max loss (send+receive); video latency, jitter, avg/max
loss, resolution, FPS (send+receive); screen sharing equivalents.

**Not obtainable:** video bitrate (Zoom 6.5.7 does not show it; field stays `nil`).
Zoom's own CPU/memory level words (Low/Medium/High) are visible but only kept as text.

## Reliability and stability

| Source | Reliability | Stability across updates |
|---|---|---|
| AX Statistics panel | High while window exists; needs window open (minimized is fine) | Medium: labels, tab names and nesting may change and are localized → isolated in `ZoomUILabels` adapter; label-driven parsing survives re-nesting |
| Native CPU/memory (`proc_pid_rusage`, `host_statistics`) | High | High (public APIs) |
| Network type (`NWPathMonitor`), proxy (`CFNetworkCopySystemProxySettings`) | High | High |
| Zoom version (`Info.plist`) | High | High |
| Meeting detection (AX window title "Zoom Meeting"/"Zoom Webinar") | High | Medium (adapter) |

## Security / permissions

- ZoomStat needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Ad‑hoc signed rebuilds may require re-granting.
- No root, no SIP changes, no code injection, no memory access, no network interception.
- Only UI side effects: opening Zoom Settings on request, selecting the Statistics category, switching its tabs. Nothing in the meeting is touched.
- AX could in principle read chat/participants; ZoomStat only walks the `Settings` window and the window list titles.
- The Zoom language must match the adapter's labels (English shipped).

## Recommendation

Implement `AccessibilityZoomStatsProvider` (AX panel, tab cycling while
minimized) + `SystemMetricsProvider` (native fallbacks), merged by
`CompositeZoomStatsProvider`. Keep all Zoom strings in one adapter file.
