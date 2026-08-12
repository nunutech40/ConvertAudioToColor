# Voice-to-Color Visualizer — Product & Technical Design

## Product
An iPhone app listens to the user's voice through the microphone, analyzes live audio, and transforms it into animated colors and visual shapes in real time. Audio is processed locally; v1 does not save or upload raw audio.

## V1 scope
- Request microphone permission only after the user taps Start.
- Start/stop microphone capture.
- Map RMS volume to brightness, orb scale, and glow.
- Map dominant frequency band to hue (FFT phase).
- Show live volume meter and states: Ready, Listening, Paused, Permission Denied, Unavailable/Failed.
- Stop capture when the app enters background/inactive; resume only after explicit user action.
- Handle denial, interruption, unavailable microphone, repeated start/stop, and audio-session errors.

Out of scope: speech-to-text, speaker/emotion detection, cloud upload, recording, ML classification, exact musical pitch detection.

## Layer map
```text
iPhone microphone hardware
  -> iOS audio subsystem
  -> AVAudioSession + AVAudioEngine
  -> AVAudioPCMBuffer / PCM samples
  -> RMS + FFT analysis
  -> Observable view-model state
  -> SwiftUI Canvas/shapes/gradients
```

## Native technologies
- AVAudioSession: permission and audio-session configuration.
- AVAudioEngine: realtime microphone input and audio tap.
- AVAudioPCMBuffer: input samples.
- Accelerate/vDSP: optional FFT/DSP.
- SwiftUI Canvas, TimelineView, gradients, shapes: rendering.
- Swift concurrency/MainActor: ownership and state delivery.

## Architecture
```text
ContentView
  -> VoiceVisualizerViewModel (@MainActor)
      -> AudioCaptureService (AVAudioSession/AVAudioEngine)
      -> AudioAnalyzer (RMS, smoothing, optional FFT)
      -> VisualizationState
```

Responsibilities:
- `AudioCaptureService`: request permission, configure/start/stop engine, deliver buffers, never own UI state, never persist/upload raw audio.
- `AudioAnalyzer`: convert buffers to compact `AudioFeatures`, keep DSP off the UI path.
- `VoiceVisualizerViewModel`: own user-visible state, map features to visualization, handle errors/lifecycle, publish on MainActor.
- `ContentView`: render state and send intents; no AVAudioEngine or DSP inside `body`.

```swift
struct AudioFeatures: Sendable {
    let normalizedVolume: Float
    let dominantFrequency: Float?
    let isSilent: Bool
}

enum ListeningState: Equatable {
    case ready
    case requestingPermission
    case listening
    case paused
    case permissionDenied
    case unavailable(String)
    case failed(String)
}
```

## Visual mapping
| Audio feature | Visual output |
|---|---|
| RMS volume/amplitude | Brightness, orb scale, glow radius |
| Dominant frequency band | Hue |
| Spectral energy | Saturation |
| Short-term peak | Pulse/ripple |
| Silence threshold | Dim/ambient state |

Suggested hue bands: low blue/purple, mid green/yellow, high orange/pink. This is an intentional visual mapping, not a scientific claim.

## Processing phases
### Phase 1: volume-only MVP
```text
PCM buffer -> RMS -> normalize 0...1 -> smooth -> brightness/scale/glow
```
### Phase 2: frequency color
```text
PCM buffer -> window -> FFT (vDSP) -> magnitudes -> dominant band -> hue
```
Clamp and smooth all values; do not drive UI directly from noisy raw FFT output.

## Lifecycle
```text
Active + Start -> request permission -> configure session -> start engine -> Listening
Background/inactive -> stop/pause engine and remove tap safely -> Paused
Foreground -> remain Paused until explicit Start
```
Do not rely on process-termination callbacks. No critical persisted state is required.

## Permission/privacy
Add to Info.plist:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is used to turn your voice into live colors.</string>
```
Ask on Start, explain local processing, never log raw audio, create no recording file, upload nothing. Denied/restricted permission gets a clear Settings recovery path.

## Failure handling
- Permission denied/restricted: clear state and Settings guidance; do not repeatedly prompt.
- Audio setup/interruption/unavailable: stop safely and show recoverable state.
- Buffer processing issue: drop the frame and continue, never crash.
- Loud input: clamp visual values.
- Repeated Start/Stop: never install duplicate taps.

## Performance
Keep audio callback lightweight; no UI work or large allocations there. Send compact features to MainActor at a bounded update rate. Do not block the main thread. Use Instruments later for CPU, allocations, and dropped frames.

## Testing
Unit-test normalization/clamping, silence, smoothing, frequency-to-hue mapping, peak bounds, and state transitions. Manually test permission, repeated start/stop, backgrounding, interruption, no raw file creation, responsiveness. Physical iPhone testing is required for real microphone validation; Simulator is insufficient.

## Implementation phases
1. SwiftUI dark visualizer using fake features, states, Start/Stop UI, preview/demo mode.
2. AVAudioSession permission + AVAudioEngine input tap, safe start/stop, RMS volume.
3. Accelerate/vDSP FFT, dominant band, hue mapping, smoothing/peak detection.
4. Lifecycle/error UI, focused tests, performance verification.

## Acceptance criteria
- Builds and launches on a real iPhone.
- Accurate microphone permission prompt appears only after Start.
- Start/Stop works repeatedly without duplicate taps.
- Volume changes brightness/scale; FFT phase changes hue.
- No raw audio persistence/transmission.
- Backgrounding, denial, interruption, and unavailable input are safe.
- Audio processing does not block UI.
- Analyzer and state transitions have focused tests.

## Codex prompt
Implement this design as a native SwiftUI iOS app. Follow phases in order, starting with Phase 1 and Phase 2 unless a working project exists. Separate audio capture, analysis, view-model state, and rendering. Use AVAudioSession and AVAudioEngine. Do not record or upload raw audio. Add microphone privacy text, lifecycle-safe start/stop, focused unit tests, and report exact build/test results. Do not claim physical-device verification unless actually run on a device.
