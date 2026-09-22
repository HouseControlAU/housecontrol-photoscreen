# Media Playback Detection

## Requirement

PhotoScreen must not start automatically while a video or other media is actively playing. A paused browser tab or an open media application must not be treated as active playback.

## Platform reality

### Linux

Linux desktops commonly expose media players through the user-session D-Bus using the MPRIS interface:

```text
org.mpris.MediaPlayer2.*
org.mpris.MediaPlayer2.Player.PlaybackStatus
```

`PlaybackStatus` has the values:

```text
Playing
Paused
Stopped
```

The Linux implementation should query every registered MPRIS player before idle startup and subscribe to `PropertiesChanged` signals. If any player reports `Playing`, PhotoScreen must not start. If playback changes to `Playing` while PhotoScreen is active, PhotoScreen should pause or exit.

MPRIS is the primary Linux implementation because it reports playback state rather than merely detecting an open browser or window.

### macOS

macOS does not provide a public API that lets a third-party application reliably query Firefox or another browser's HTML5 media element state. In particular, PhotoScreen cannot directly read Firefox/YouTube's internal JavaScript `paused` property.

The following are not reliable as a universal solution:

- `NSWorkspace` running-application state
- Browser process detection
- Window titles
- Fullscreen-window detection
- `MPNowPlayingInfoCenter` (applications publish their own state; it is not a general query API)
- MPRIS (Linux/D-Bus only)

Some media players hold an I/O Power Management assertion while playing, but Firefox/YouTube is not required to do so. Assertions are therefore useful evidence, not a complete solution.

## Current macOS fallback

The macOS development build uses conservative heuristics:

1. Inspect the frontmost browser/media-player application.
2. Check the window title for known media services.
3. Treat a browser or known media-player window covering almost the entire display as likely fullscreen media.
4. Suppress idle startup when the heuristic matches.

This is intentionally biased toward not starting PhotoScreen. It can still miss Firefox/YouTube playback when Firefox exposes neither a useful title nor a detectable fullscreen window, and it can conservatively suppress startup for paused fullscreen content.

This fallback must not be described as authoritative playback detection.

## Reliable macOS options

To obtain authoritative browser playback state on macOS, use one of these designs:

### 1. Browser extension plus native messaging (recommended if macOS support is required)

A Firefox/Chrome extension observes media elements and reports:

```text
playing
paused
ended
```

The extension communicates with a signed native helper through Native Messaging. PhotoScreen queries the helper over a local authenticated Unix socket or reads a small local state record.

The extension must report only aggregate state; it must not collect URLs, page content, or customer data.

### 2. Player-specific integrations

Implement optional integrations for VLC, IINA, mpv, and other players that expose a documented control API. This is more reliable than process detection but does not solve arbitrary browser playback.

### 3. User-controlled pause

Provide a menu-bar pause switch and a keyboard shortcut as a guaranteed fallback. This is not automatic detection, but it gives the user a deterministic override when a browser does not expose playback state.

## Startup decision

The startup decision should use this order:

```text
if userPaused:
    do not start
else if authoritativePlayerState == Playing:
    do not start
else if platformFallbackSaysMediaLikelyActive:
    do not start
else:
    allow idle startup
```

The fallback must never claim `Playing`; it should be represented as `mediaLikelyActive` so diagnostics can distinguish heuristic suppression from authoritative state.

## Diagnostics

Add a diagnostic status to Settings or a debug log:

```text
Media detection: MPRIS Playing
Media detection: browser extension Playing
Media detection: fullscreen heuristic
Media detection: no active media
Media detection: unavailable
```

This is required for field troubleshooting. A report that only says "unable to detect media" is insufficient.

## Acceptance tests

### Linux

- MPRIS player reports `Playing`: PhotoScreen does not start.
- MPRIS player changes `Paused` to `Playing`: active PhotoScreen pauses or exits.
- MPRIS player reports `Paused`: PhotoScreen may start after idle.
- Browser is open with no MPRIS player or playback: PhotoScreen may start.

### macOS fallback

- Fullscreen browser video with a detectable browser window: PhotoScreen does not start.
- Windowed browser video with a media title: PhotoScreen does not start.
- Paused browser tab: behavior is conservative and must be shown as heuristic suppression.
- Browser with unrelated content: PhotoScreen is not blocked solely because the browser is running.

### macOS authoritative mode

- Extension reports `Playing`: PhotoScreen does not start.
- Extension reports `Paused` or `Ended`: idle startup is permitted.
- Extension/helper unavailable: fallback behavior and diagnostic status are used.

## Product decision

Linux production deployments should use MPRIS as the required playback interface. macOS should retain the heuristic fallback for development, but reliable Firefox/YouTube detection requires a browser extension/native helper or an explicit user pause control. No heuristic should be presented as guaranteed playback detection.
