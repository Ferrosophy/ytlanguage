# Host compatibility

Each entry is a device observation reported by the user, not an assumption from headers.

## YouTube 21.37.5 · iOS 27.0.1 · ESign injection

Other injected tweaks: YTVideoOverlay, YTLite, YouTubeX, YouQuality, YouPiP, YTABGoodies,
YouGroupSettings, YTLoginFix, libellekit.

| Signal | API used | Evidence | Result |
|---|---|---|---|
| Injection, overlay button | `YTSettingsSectionItemManager +registerTweak:metadata:` (YTVideoOverlay) | v0.1.0 screenshot | PASS |
| Video ID | `YTPlayerViewController -currentVideoID` | v0.1.0 `7AhTatRD0gs`, v0.2.0 `B8B8A1B1he8` | PASS |
| Clock / duration | `-currentVideoMediaTime`, `-currentVideoTotalMediaTime` (seconds) | matches player UI | PASS |
| Caption track metadata | `activeVideo.playerItem.captionController.activeCaptionTrack` → `MLInnerTubeCaptionTrack` (`languageCode`, `trackName`, `VSSID`, `trackType`) | v0.2.0 report: `en`, "英文 (自動產生)", `a.en` | PASS |
| Caption cues | `MLFormat3Captions -captions` → `YTIntervalTree` of `MLCaption` (`startTime`/`endTime` in seconds, `segments[].text`) | v0.2.0 report | PASS |
| Cue at current time | lookup by player clock | 01:47.751 → the two on-screen cues | PASS (single position) |

### v0.3.0 (M1), user report 2026-10-28
The bilingual overlay, translation, hiding YouTube's native captions, long-press lookup, word saving and
pause-on-lookup all work, with no bugs reported. No diagnostics file came with it, so which translation source
was used and the result of the `pause`/`play` check were not recorded.

### v0.4.0 diagnostics (user, 2026-10-28)
- `seekToTime:` is available and the video title was found through `videoDetails.title`.
- The runtime dump lists these methods on YTPlayerViewController: `play`, `pause`, `arePlayerControlsHidden`,
  `playbackControllerDidStartPIP:` / `DidStopPIP:`, and `seekToTime:seekSource:`.
- It lists these on YTCaptionViewController: `setCaptionsHidden:`, `captionView`, and `setCaptionsBottomPadding:`.
- 37 caption tracks were found: the auto-generated ones (`a.xx`, type 0) and auto-translated ones
  (`ta.<src>.<dst>`, type 2, names without "自动"). Up to v0.4.0 a `ta.en.zh-Hans` track would have been taken
  as human-made. v0.5.0 excludes VSSID `ta.*` and trackType 2.

### v0.5.0 diagnostics (user, 2026-10-28, video `7AhTatRD0gs`)
- Taken after CC was switched off: `activeCaptionTrack: nil` while the old `MLFormat3Captions` document stayed
  alive. v0.6.0 uses a nil active track as "CC off".
- The progress bar was no longer covered, but the position setting appeared broken, so `arePlayerControlsHidden`
  alone is not trusted any more; v0.6.0 also checks whether the overlay button is visible.

### v0.6.0 – v0.8.1 (user reports + v0.8.0 diagnostics, 2026-10-28)
v0.8.1 was confirmed "完全ok" by the user. Verified on device:
- **CC off**: `activeCaptionTrack: nil` hides the YTLanguage subtitles.
- **Controls**: `arePlayerControlsHidden` and the YTVideoOverlay button visibility agree, and the lift above the
  progress bar works.
- **Placement**: the subtitle view sits below `YTMainAppControlsOverlayView` in the same parent
  (`overlay below controls {{0, 0}, {844, 390}}`), so play/pause and native side panels stay on top.
- **Native captions**: re-hidden in the same frame through the YTCaptionViewController `viewDidLayoutSubviews` /
  `setCaptionsHidden:` hooks plus a display link. There is no flash when the controls toggle.
- **Settings**: a 双语学习 category in the Tweaks group, via YouGroupSettings `+[YTSettingsGroupData tweaks]`, opens
  the study page full screen.
- **Lists and export**: the transcript drawer, long press → 收藏句子, word/sentence lists, and TXT/CSV/JSON plus
  Markdown export.

### Still unverified
- Hiding YouTube's captions in PiP; DeepSeek requests; pause-on-lookup (`pause`/`play` exist, effect not measured).
- Human-made Chinese tracks (no test video had one); videos without captions; live streams.

### v0.2.0 caption report, video `B8B8A1B1he8` (21:54.563, auto-generated English)
- 1 live `MLFormat3Captions` document, created when the video loaded, so it maps cleanly to the current video.
- 287 cues, 00:00.080 → 21:47.159, which is 99.4% of the duration. The last 7 s have no speech.
- The host's enumeration is already sorted by start time. There are 0 cues with end < start, 0 gaps > 10 s, and 0 cues with empty text.
- 286 of the cues overlap the previous one. This is the roll-up display of auto captions: the next cue appears while the previous one is still shown. The cue texts themselves don't repeat, so concatenating them in order gives the transcript.
- Segment text uses `\n` to separate the two display lines.

### Runtime facts useful later (not yet exercised)
- `MLInnerTubeCaptionController` has `availableCaptionTracks`, `setSelectedCaptionTrack:selectionReason:`,
  `loadCaptionsWithTrack:selectionReason:`, `userVisibleCaptionTracks` and the ivar `_autoTranslationEnabled`.
  These are candidates for using YouTube's own translated tracks in M1, before trying any external translator.
- `MLFormat3Captions -copyWithStartTime:endTime:` exists. Windowed copies may show up for long or live
  videos, so completeness must stay a measured value per document.

### Not yet covered
- Human-made captions, captions in other languages, videos without captions, live streams.
- An explicit seek test, i.e. two reports at different positions.
