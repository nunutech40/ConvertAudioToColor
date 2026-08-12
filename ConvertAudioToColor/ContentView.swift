import SwiftUI

struct ContentView: View {
    @StateObject private var model = VoiceVisualizerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VisualizerCanvas(state: model.visual)

            VStack {
                header
                Spacer()
                controls
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("VOICE TO COLOR")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                Spacer()
                Circle()
                    .fill(model.state == .listening ? .green : .gray)
                    .frame(width: 9, height: 9)
                Text(model.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(model.affect.family.rawValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
            }

            HStack {
                Text("valence \(model.affect.valence, specifier: "%.2f")")
                Text("arousal \(model.affect.arousal, specifier: "%.2f")")
                Spacer()
                if model.hasReplay {
                    Text("Replay available").foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(primaryButtonTitle) {
                if model.state == .listening { model.stop() }
                else if model.state == .playing { model.stopReplay() }
                else { model.start() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)

            if model.hasReplay {
                Button("Replay", action: model.replay).buttonStyle(.bordered)
                Button("Discard", action: model.discard)
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
    }

    private var primaryButtonTitle: String {
        if model.state == .listening { return "Stop" }
        if model.state == .playing { return "Stop replay" }
        return "Start"
    }
}

struct VisualizerCanvas: View {
    let state: VisualizationState

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let breathing = sin(time * 1.4) * 0.025
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.19 * (state.orbScale + breathing)
                let color = Color(hue: state.hue, saturation: state.saturation, brightness: state.brightness)
                let orb = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: state.glowRadius))
                    layer.fill(orb, with: .color(color.opacity(0.18)))
                }
                context.fill(orb, with: .radialGradient(
                    Gradient(colors: [color, color.opacity(0.45), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                ))
                context.stroke(orb, with: .color(color.opacity(0.8)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
