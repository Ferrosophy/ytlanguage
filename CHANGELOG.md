# YTLanguage Changelog

Release builds are only made at milestone steps; each one has a version from `VERSION`
and is written to `dist/YTLanguage-v<version>.dylib`.

## 0.8.1 — 2026-10-28 — first public source release (M4)

Device result (user, 2026-10-28): "完全ok". The study page opens correctly from settings, and the native captions no
longer flash.

## 0.8.1 build notes
- **Study page opens full screen** in its own UIKit navigation with a close button, no longer pushed into
  YouTube's settings navigation, where the back arrow was drawn off-screen.
  - The v0.8.0 embed never matched: the screenshot showed the page opened from the 单词 row. The embed is removed.
  - Instead, a `UINavigationController -pushViewController:animated:` hook acts only while a YTSettingsViewController
    is on top, and replaces the pushed 双语学习 page with the study page. The pushed page is recognised by its title
    or by its section keys.
  - Diagnostics add `settings push:` with the pushed class, title and keys, in case it still does not match. The
    单词 / 句子 rows stay as the fallback and also open full screen.
- **YouTube captions no longer flash** when the controls show or hide. The hiding used to run only on the 0.15 s
  tick, while YouTube re-shows its captions on relayout. Now the view and its `captionView` are re-hidden in the
  same pass:
  - from YTCaptionViewController `viewDidLayoutSubviews` / `setCaptionsHidden:` hooks;
  - from a display link that runs only while hiding is on.

## 0.8.0 — 2026-10-28

Device result (user + diagnostics, 2026-10-28):
- Export buttons are present, and the CC-off rule works.
- The subtitle overlay is placed below the controls (`overlay below controls {{0,0},{844,390}}`), and the
  controls signals agree.
- Problems: the back arrow is still off-screen, and YouTube captions flash when the controls toggle. Both are
  addressed in 0.8.1.

## 0.8.0 build notes
- **The 双语学习 settings page is the study page**: YTLStudyViewController is embedded as a child of YouTube's
  settings page, covering the settings list (YouTube's header and back button stay). It is embedded only when
  the page's `settingsSectionControllers` holds exactly our category; otherwise the 单词 / 句子 rows remain as
  the fallback.
- The study page header now holds the 单词 / 句子 tabs and an export button, so it no longer depends on a
  navigation bar (in 0.7.0 the back button was misaligned when pushed into YouTube's navigation).
- **Export saved words or sentences** (the current tab) as TXT, CSV or JSON through the share sheet.
  - Words: word, translation.
  - Sentences: sentence, translation, video title, link with start time, start time.
  - CSV has a UTF-8 BOM.
- **Export the whole transcript** with the new share button in the 字幕 drawer: Markdown, original text only. It
  holds the title, the video link, then one paragraph per sentence.

## 0.7.0 — 2026-10-28

Device result (user screenshots, 2026-10-28): the 双语学习 settings section and the study page work (1 saved
word shown). The pushed page's back button was misaligned. Export was missing. Fixed in 0.8.0.

## 0.7.0 build notes
- **双语学习 moved to YouTube settings**, Tweaks group (next to YouPiP and 播放器按钮). It has two rows, 单词 and
  句子, each showing a count and opening the same page as before. The 我的-tab top-bar button from 0.6.0 is gone.
  Mechanism: a settings category (2617) added the way YouPiP / YTVideoOverlay do it. With YouGroupSettings, the
  category is appended to `+[YTSettingsGroupData tweaks]`; without it, it goes first in group type 1. Icon
  `YT_TRANSLATE`.
- **Subtitles go under YouTube's controls**: the subtitle view is inserted just below `YTMainAppControlsOverlayView`
  in the same parent, with the same frame, so play/pause draw on top of it.
  - A transparent proxy on top of the player forwards long presses on the original line. While the controls are
    visible it passes every touch through, so word lookup waits until the controls hide.
  - Because the frame follows the controls overlay, side panels (comments etc.) that narrow the controls area
    also narrow the subtitles instead of being covered.
  - Falls back to the old on-top placement when the controls overlay is missing, hidden or shorter than 60 % of
    the player. Diagnostics show the placement and the frame.

## 0.6.0 — 2026-10-28 — M3, not yet device-tested
- **CC off hides our subtitles too**: when YouTube's CC is switched off, `activeCaptionTrack` is nil (seen in the
  v0.5.0 diagnostics taken after CC was turned off), and the overlay now shows nothing. Mode 关闭 + CC on still
  gives YouTube's own captions. If the caption controller cannot be read, the old behaviour is kept.
- **Position setting works again**: the subtitle is lifted above the progress bar only while the controls are
  visible; otherwise it sits at the set X/Y. Visibility now needs two signals to agree: `arePlayerControlsHidden`
  and whether our YTVideoOverlay button (inside `YTMainAppControlsOverlayView`) is actually visible up its view
  chain. While the style page is open the set position is always shown. Diagnostics print both signals.
- **Transcript long press**: only 收藏句子 (plus 取消). The editor, 从这里播放 and copy actions are gone, and so
  is the word card's 收藏整句 button.
- **M3 双语学习** page: 单词 / 句子 tabs at the top; each tab shows 原文 / 译文 / 原文与译文 (remembered per tab);
  newest first; swipe to delete.
  - Entry (replaced in 0.7.0): a 双语学习 button in YouTube's top bar, only while the 我的 tab is the current top-level page. Signals:
    `YTPivotBarItemView.renderer.pivotIdentifier` (`FElibrary`), the selected tab item or else the last tapped
    tab, `YTRightNavigationButtons` as anchor and `YTHeaderViewController -isTopLevelPage` (all YouTubeHeader,
    none verified on device). The diagnostics report adds a 我的入口 line with what was observed.
  - Also reachable from the panel: tap 已收藏单词 / 已收藏句子.

## 0.5.0 — 2026-10-28

Device result (user + diagnostics, 2026-10-28): the progress bar is no longer covered, but the position setting
stopped working; subtitles stay after CC is turned off; the transcript long-press menu had too many options.
All fixed in 0.6.0.

## 0.5.0 build notes
- **Portrait and PiP**: no subtitles. YTLanguage's overlay is hidden and YouTube's caption view is hidden too.
  - Portrait = the window is taller than it is wide.
  - PiP is detected by hooking `playbackControllerDidStartPIP:` / `DidStopPIP:` (listed in the v0.4.0 runtime dump;
    installed only if both exist). During PiP, YouTube's captions are switched off with `YTCaptionViewController
    -setCaptionsHidden:`, and afterwards only the ones YTLanguage switched off are restored.
  - Translation keeps running, so the transcript list still fills in.
  - Exception: the style editor preview still shows.
- **Progress bar**: while the player controls are visible (`arePlayerControlsHidden` == NO, runtime-observed), the
  bubble's bottom is kept above 76 % of the player height. The move is animated, and the bubble returns when the
  controls hide.
- **Long-press offset fixed**: subtitle text is now drawn and hit-tested with the same TextKit layout
  (`YTLTextLayoutView`). Before, UILabel drew the text and a separate TextKit copy mapped the touch. A touch counts
  if it lands within 8 pt of a text line.
- **Translation**: SiliconFlow removed, along with its old Keychain item and model setting, which are deleted on
  launch. New setting 翻译服务 Google / DeepSeek.
  - DeepSeek uses `https://api.deepseek.com/chat/completions` (OpenAI-compatible, Bearer key), default model
    `deepseek-flash` per api-docs.deepseek.com on 2026-10-28; the model is editable.
  - The chosen service runs first and the other is the fallback; DeepSeek is used only when a key is set.
  - A human Simplified Chinese track is still preferred.
  - Word lookup: Google dictionary, then DeepSeek if a key is set.
- **Human Chinese track fix**: auto-translated tracks (VSSID `ta.<src>.<dst>`, trackType 2; seen in the v0.4.0
  diagnostics with plain names like 中文（繁體）) are now excluded. Before, a `ta.en.zh-Hans` track would have been
  treated as human-made.
- **Settings text trimmed**: all panel and style-page footers removed, 字幕样式 without the parenthesis,
  position rows are just X / Y.
- **Saving sentences**:
  - The transcript list now uses its own long press with an action sheet: 收藏整句 / 选择·编辑后收藏 /
    从这里播放 / 复制原文 / 复制译文. The v0.4.0 table context menu never appeared, because the drawer lives in the
    window without a view controller.
  - The word card gained a 收藏整句 button, so a sentence can also be saved straight from the video subtitle.

## 0.4.0 — 2026-10-28 (M2 transcript drawer + subtitle style)

Device result (user report + diagnostics, 2026-10-28):
- Working: subtitle style, the drawer, Google translation (368/368 sentences), `seekToTime:` available, video title found.
- Problems, fixed in 0.5.0: the subtitle covered the progress bar; the long-press position was off after moving
  the subtitle; long-pressing a sentence showed no save option.
- Also requested: no subtitles in portrait or PiP, trimmed settings text, SiliconFlow replaced by DeepSeek.

## 0.4.0 build notes
- **Subtitle style** (面板 › 字幕样式), live preview with sample text while the page is open:
  - text: size 10–40 pt, weight (常规/中等/粗体/特粗), effect (无/阴影/描边), original and translation colors;
  - background: on/off, color with alpha, blur 0–100 % (paused UIViewPropertyAnimator), padding, max width
    (% of player) and corner radius. The text is always laid out inside the background, so padding/width changes
    re-wrap it;
  - position: X/Y of the bubble center in % of the player (slider or typed number); the bubble is clamped inside
    the player;
  - stored as one dictionary in NSUserDefaults (`YTLanguage-SubtitleStyle`), with a reset button.
- **Shorter segments**: new setting 单句最多词数 (8–40, default 18). A segment is cut at a clause mark or before a
  conjunction (and/but/so/because/which/…) once it reaches 60 % of the limit, at the limit, or after 8 s on
  screen. Changing the limit re-splits the current video (cached translations are reused).
- **Word card**: close button (top right); the lookup sheet still also dismisses by swiping down.
- **M2 transcript drawer** (second player button `YTLTranscript`, or 面板 › 打开字幕列表):
  - portrait: slides in from the right below the inline player (video stays visible), left strip dims and closes on
    tap; landscape: right panel at 38 % width (320–460 pt), the video stays usable on the left;
  - rows show timestamp, sentence and translation (machine translation, or the human Chinese track cues overlapping
    the sentence); the current row is highlighted;
  - auto-follow; manual scrolling pauses it and shows 回到当前句; there is also a 跟随 toggle;
  - tap a row → `seekToTime:` (declared in YouTubeHeader, checked at runtime);
  - long press: 从这里播放 / 收藏整句 / 选择·编辑后收藏… / 复制原文 / 复制译文;
  - the status line shows sentence count, completeness (完整 or 部分 a–b %) and translation progress; empty state
    asks to turn on CC; it follows video changes and closes itself when the player leaves the screen.
- **Saved sentences** go to `saved_sentences`: text (selection or edited text), translation (whole sentence only),
  video ID, title, start/end ms. The title comes from `activeVideo.singleVideo.playbackData.video.videoDetails.title`;
  that path is from YouTubeHeader, but `title` itself is unverified, so the title is saved as NULL when unavailable.
- The panel shows the saved sentence count. Diagnostics add the drawer state, max words, whether `seekToTime:` is
  available and whether the video title was found.

## 0.3.0 — 2026-10-27 (M1: bilingual subtitles + word lookup)

Device result (user, 2026-10-28): every M1 feature works, no bugs reported. Requests for the next version:
subtitle style/background/position settings, a close button on the word card, shorter segments.

## 0.3.0 build notes
- **Subtitle overlay** on YTPlayerViewController's view, in four modes: 双语 / 原文 / 译文 / 关闭.
  - The source is the host's `MLFormat3Captions` document (the CC track YouTube loaded).
  - Cues are merged into sentences: word times are interpolated inside each cue; sentences split at `.?!`, at speaker
    marks (`>>`), after pauses over 2 s, at a comma once a sentence passes 25 words, and always at 40 words.
  - While the overlay shows text, YouTube's own caption view controllers (`YTCaptionViewController`) are hidden.
    YTLanguage only un-hides the ones it hid itself.
  - Video changes are followed through `currentVideoID`. During ads (`isPlayingAd`) nothing is shown.
- **Translation to Simplified Chinese**, in this order:
  1. A human-made Simplified Chinese track from `availableCaptionTracks`, downloaded from the track's own `URL`.
     Tracks are excluded when `VSSID` starts with `a.` or the name contains 自动/自動/翻译/auto-generated/translated.
  2. Google `translate_a/single?client=gtx` (no key): batches of 25 sentences, sent one at a time, cached in memory.
  3. SiliconFlow chat completions, only if the user saved a key. The key is stored in the Keychain.
     The default model is `Qwen/Qwen2.5-7B-Instruct`, and it can be edited in the panel.
  4. Otherwise the original text is shown; a failed request is retried after 15 s.
- **Long-press word lookup** on the original line:
  - The pressed word is highlighted and the overlay stops updating while the card is open.
  - A sheet shows the Chinese meaning (Google `dt=bd`, falling back to SiliconFlow), the sentence and its translation,
    a 收藏单词 button and a 系统词典 button (UIReferenceLibraryViewController).
  - Optional pause on lookup, experimental: only used if YTPlayerViewController responds to `pause`/`play`.
    The result is checked against the media clock and reported in diagnostics. Playback resumes only if YTLanguage
    paused it and the user did not seek.
- **Saved words** go to SQLite (`Application Support/YTLanguage/ytlanguage.sqlite`, schema v1): `saved_words` with
  upsert on (language, normalized key). The `saved_sentences` table is created now for M2.
- **Player button** now opens a panel with mode, translation status, SiliconFlow key and model, pause toggle,
  saved-word count and the diagnostics report.
- **Diagnostics** gain: the caption track list, overlay/session/translation status, and YTPlayerViewController
  methods matching pause/play/seek/rate/state.
- Core (`Sources/Core`) has fixture tests in `Tests/CoreTests.m`. They do NOT run here: Ubuntu's GNUstep uses the GCC
  ObjC runtime, which clang-compiled code cannot link against. See `Tests/run.sh`. The cases were traced by hand only.

## 0.2.0 — 2026-10-27 (M0 caption probe)
- Version number in the release file name, the probe title and the load log.
- Player button now opens a caption probe report (scrollable, Share exports the full .txt):
  - video ID, clock and duration;
  - the documented YouTubeHeader caption path (activeVideo → playerItem → captionController →
    active/selected caption track) with the track's scalar/string properties (URLs/tokens redacted);
  - every live `MLFormat3Captions` document (captured via `+allocWithZone:` / `-captions` hooks,
    observation only), with cue count, units, range, sort order, end<start, overlaps, gaps,
    empty text and coverage vs. video duration;
  - the cue at the current time (for seek checks) and the first five cues;
  - runtime ivar/method lists of the caption classes, for the next iteration's evidence.
- Caption hooks install only if `MLFormat3Captions -captions` exists in the host.
- Sources split into `Sources/HostAdapter` and `Sources/UI`.

Device result (user report, YouTube 21.37.5 / iOS 27.0.1, video `B8B8A1B1he8`, auto-generated English):
- Caption track metadata and the full cue list were read: 287 cues covering 99.4% of the video, sorted, with no bad
  timestamps. Details are in `docs/COMPATIBILITY.md`.
- M0 caption gate: PASS. Seeking has been checked at one position only; it gets re-tested in M1.

## 0.1.0 — 2026-10-27 (device-verified)
Shipped without a version string, as `dist/YTLanguage.dylib`,
SHA-256 `b5238443a502b6b70c25d1bade6213ccaa8604e4091b8955cd3df72d08bd08d9`.
- Player top-row button registered through YTVideoOverlay; floating-badge fallback without it.
- Tapping shows video ID, playback clock, player VC class, host and iOS version.

Device result (user, iOS 27.0.1, YouTube 21.37.5 IPA with YTVideoOverlay, YTLite, YouTubeX, YouQuality, YouPiP, etc.):
- Injection via ESign: PASS
- Button in the player top row next to speed / CC / settings: PASS
- Video ID (`7AhTatRD0gs`) and clock (0:41 / 16:57, matches player UI): PASS
- Full timestamped caption track: NOT YET IMPLEMENTED — remaining M0 item
