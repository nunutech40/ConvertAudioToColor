# Voice-to-Color Visualizer — Product & Technical Design

## Product

An iPhone app listens to the user's voice, analyzes its acoustic characteristics locally, and transforms them into animated colors and visual shapes. The current session's PCM audio may be retained temporarily in RAM so the user can replay it. Audio is never written to disk or uploaded.

## V1 scope

- Request microphone permission only after the user taps Start.
- Start/stop microphone capture and analyze audio in real time.
- Retain a bounded in-memory session buffer for local replay; do not create a recording file.
- Replay the current temporary session on explicit user action.
- Extract energy, spectral sharpness, tension, pitch variation, pauses, and speech rhythm.
- Map features to continuous valence/arousal coordinates, then to a mood family and intensity.
- Map mood coordinates to hue, saturation, brightness, shape, motion, and glow.
- Show live mood visualization and states: Ready, Listening, Paused, Permission Denied, Unavailable/Failed, Playing.
- Stop capture when the app enters background/inactive; resume only after explicit user action.

Out of scope: speech-to-text, claims of reading a user's true subjective emotion, cloud upload, permanent recording, ML classification, and exact musical pitch detection.

## Layer map

```text
iPhone microphone hardware
  -> iOS audio subsystem
  -> AVAudioSession + AVAudioEngine
  -> AVAudioPCMBuffer / PCM samples (temporary RAM)
  -> AudioAnalyzer (RMS, FFT, spectral/pitch/time features)
  -> AffectMapper (valence/arousal + mood family)
  -> VisualizationMapper
  -> Observable view-model state
  -> SwiftUI Canvas/shapes/gradients

Temporary PCM buffers
  -> AudioReplayService
  -> AVAudioPlayerNode
  -> iPhone speaker
```

## Native technologies

- `AVAudioSession`: microphone permission and audio-session configuration.
- `AVAudioEngine`: real-time microphone input and audio tap.
- `AVAudioPCMBuffer`: temporary PCM samples in RAM.
- `Accelerate/vDSP`: windowing, FFT, magnitudes, spectral centroid, and spectral flux.
- In-memory PCM session store: bounded temporary replay buffer; no file persistence.
- `AVAudioPlayerNode`: replay scheduled `AVAudioPCMBuffer` chunks locally.
- SwiftUI `Canvas`, `TimelineView`, gradients, shapes: rendering.
- Swift concurrency/MainActor: ownership and state delivery.

## Architecture

```text
ContentView
  -> VoiceVisualizerViewModel (@MainActor)
      -> AudioCaptureService (AVAudioSession/AVAudioEngine)
      -> InMemoryAudioSession (bounded PCM buffers)
      -> AudioAnalyzer (RMS, FFT, time/spectral features)
      -> AffectMapper (valence/arousal and mood labels)
      -> VisualizationMapper
      -> AudioReplayService (AVAudioEngine/AVAudioPlayerNode)
      -> VisualizationState
```

Responsibilities:

- `AudioCaptureService`: request permission, configure/start/stop engine, and deliver buffers; never own UI state.
- `InMemoryAudioSession`: retain bounded PCM chunks only for the current session; expose replay data and clear it explicitly.
- `AudioAnalyzer`: convert buffers to compact `AudioFeatures`; keep DSP off the UI path.
- `AffectMapper`: apply the selected research-informed valence/arousal model and map coordinates to a mood family; this is product logic, not an iOS API.
- `VisualizationMapper`: convert affect coordinates and intensity into color and motion parameters.
- `AudioReplayService`: schedule temporary PCM buffers to `AVAudioPlayerNode`; never export or write them to disk.
- `VoiceVisualizerViewModel`: own user-visible state, coordinate services, handle errors/lifecycle, and publish on MainActor.
- `ContentView`: render state and send intents; no AVAudioEngine or DSP inside `body`.

```swift
struct AudioFeatures: Sendable {
    let energy: Float
    let spectralSharpness: Float
    let spectralFlux: Float
    let pitchVariation: Float
    let pauseRatio: Float
    let speechRhythm: Float
    let isSilent: Bool
}

struct AffectState: Sendable {
    let valence: Float       // negative ... positive
    let arousal: Float       // low energy ... high energy
    let family: EmotionFamily
    let intensity: Float
}

enum ListeningState: Equatable {
    case ready
    case requestingPermission
    case listening
    case paused
    case playing
    case permissionDenied
    case unavailable(String)
    case failed(String)
}
```

The app should call this an affect or mood interpretation, not definitive emotion detection. Audio can suggest acoustic activation and pleasantness, but cannot reliably know the user's inner state without context or self-report.

## Visual mapping

| Input | Visual output |
|---|---|
| Valence/arousal coordinates | Position in the color-emotion space |
| Emotion family | Base hue / palette |
| Arousal and intensity | Saturation, brightness, scale, glow, and motion |
| RMS energy | Brightness, orb scale, and glow radius |
| Spectral sharpness and pitch | Hue offset / color temperature |
| Spectral flux | Pulse, ripple, and jitter |
| Silence/pause ratio | Dim or ambient state |

Use a research-informed but explicitly configurable palette. Color-emotion associations are systematic but many-to-many and depend on hue, lightness, saturation, context, and culture. Use a wheel of families such as sadness, anger, fear, joy, trust, surprise, disgust, and anticipation; use lightness/saturation for intensity. The palette is a visual interpretation, not a claim that one emotion has one universal color.

## Emotion model and mapping

Use Russell's circumplex model as the continuous foundation:

- `valence`: unpleasant/negative to pleasant/positive.
- `arousal`: low energy/calm to high energy/activated.

Use emotion-family labels inspired by Plutchik only as a vocabulary and visual breakdown. Plutchik is not a universal ground truth or an automatic classifier.

```text
AudioFeatures
  -> normalize and smooth
  -> AffectMapper
  -> valence + arousal
  -> emotion family + intensity
  -> color-wheel position
  -> hue + saturation + brightness + motion
```

The initial `AffectMapper` is a deterministic, testable ruleset based on valence/arousal. It is not a pre-existing Apple algorithm. Its coefficients and thresholds are tunable product configuration and must be validated with user testing. A future ML model is a separate phase.

Suggested initial families:

| Family | Valence | Arousal | Initial visual direction |
|---|---:|---:|---|
| Sadness | negative | low | blue-indigo, dim, slow, downward |
| Anger | negative | high | red, saturated, fast, sharp |
| Fear/anxiety | negative | high/unstable | blue-violet, trembling, irregular |
| Joy | positive | medium-high | yellow-orange, bright, expanding |
| Trust/calm | positive/light | low | teal-green, stable, flowing |
| Surprise | mixed | high/spiky | bright magenta-yellow, sudden pulse |
| Disgust | negative | medium | muted green-yellow, distorted motion |
| Anticipation | positive/light | rising | orange-pink, forward/increasing motion |

These are palette anchors, not universal psychological facts. Research shows color associations are reliable enough to inform a starting palette, but not deterministic; brightness, saturation, hue, context, and culture matter.

## Processing phases

### Phase 1: acoustic features and affect coordinates

```text
PCM buffer -> AudioAnalyzer -> normalize -> smooth -> AudioFeatures
AudioFeatures -> AffectMapper -> valence/arousal -> mood family/intensity
```

### Phase 2: frequency color and visual mapping

```text
PCM buffer -> window -> FFT (vDSP) -> magnitudes
           -> spectral features -> VisualizationMapper -> Canvas
```

Clamp and smooth all values; do not drive UI directly from noisy raw FFT output.

### Phase 3: bounded in-memory replay

```text
PCM buffers -> InMemoryAudioSession (RAM only, bounded duration)
             -> AudioReplayService -> AVAudioPlayerNode -> speaker
```

Replay is explicit and local. Use a maximum session duration or memory budget. When the limit is reached, either stop accepting more replay audio or discard the oldest chunks according to the chosen product policy. The policy must be visible in the UI.

## Lifecycle

```text
Active + Start -> permission -> configure session -> start engine -> Listening
Listening -> copy bounded PCM chunks to RAM and analyze them in parallel
Stop -> remove tap -> Ready with replay available while session buffer exists
Replay -> schedule RAM buffers -> Playing -> stop/complete -> Ready
Background/inactive -> stop capture and playback, remove tap safely -> Paused
Foreground -> remain Paused until explicit Start; apply session-clear policy
```

Do not rely on process-termination callbacks. No critical state is persisted.

## Permission and privacy

Add to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is used to turn your voice into live colors and let you replay this session.</string>
```

Ask on Start, explain local processing and temporary in-memory replay. Never log raw audio, create a recording file, or upload anything. Clear the session buffer when the user discards it, when the session expires, and according to the background policy. Denied/restricted permission gets a clear Settings recovery path.

## Failure handling

- Permission denied/restricted: clear state and Settings guidance; do not repeatedly prompt.
- Audio setup/interruption/unavailable: stop safely and show a recoverable state.
- Buffer processing issue: drop the frame and continue; never crash.
- Replay buffer limit reached: show a clear limit state and apply the configured retention policy; never grow memory without bound.
- Replay format/session error: stop playback safely and keep live visualization available.
- Loud input: clamp visual values.
- Repeated Start/Stop: never install duplicate taps.

## Performance

Keep the audio callback lightweight; no UI work or unbounded allocations there. Copy only bounded PCM chunks for replay, analyze off the UI path, and send compact features to MainActor at a bounded update rate. Do not block the main thread. Use Instruments to measure CPU, allocations, replay duration, and dropped frames.

## Testing

Unit-test normalization/clamping, silence, smoothing, feature extraction, valence/arousal mapping, emotion thresholds, color-wheel mapping, replay limits, and state transitions. Manually test permission, repeated start/stop, replay, discard, backgrounding, interruption, no raw file creation, bounded memory, and responsiveness. Physical iPhone testing is required for real microphone and speaker validation; Simulator is insufficient.

## Implementation phases

1. SwiftUI dark visualizer using fake `AudioFeatures` and `AffectState`, color-wheel palette, and preview/demo mode.
2. `AVAudioSession` permission + `AVAudioEngine` input tap, safe start/stop, RMS volume, and bounded in-memory PCM session.
3. vDSP spectral features, deterministic valence/arousal `AffectMapper`, smoothing, color mapping, and focused tests.
4. Local replay with `AVAudioPlayerNode`, lifecycle/error UI, memory limits, and performance verification.

## Acceptance criteria

- Builds and launches on a real iPhone.
- Microphone permission prompt appears only after Start.
- Start/Stop works repeatedly without duplicate taps.
- Acoustic features change valence/arousal and the resulting visual mood.
- Intensity changes brightness, scale, glow, and motion.
- Current session can be replayed locally from bounded RAM buffers.
- No raw audio persistence/transmission and no unbounded memory growth.
- Backgrounding, denial, interruption, and unavailable input are safe.
- Audio processing does not block UI.
- Analyzer, affect mapping, replay limits, and state transitions have focused tests.

## Codex prompt

Implement this design as a native SwiftUI iOS app. Follow phases in order, starting with the fake-feature visualizer and bounded in-memory session model. Separate capture, temporary RAM storage, analysis, affect mapping, replay, view-model state, and rendering. Use `AVAudioSession`, `AVAudioEngine`, Accelerate/vDSP, and `AVAudioPlayerNode`. Do not write or upload raw audio. Add microphone privacy text, lifecycle-safe start/stop, explicit replay/discard controls, a memory/duration limit, focused unit tests, and report exact build/test results. Treat affect mapping as deterministic product logic grounded in valence/arousal research, not as a built-in emotion detector. Do not claim physical-device verification unless actually run on a device.
