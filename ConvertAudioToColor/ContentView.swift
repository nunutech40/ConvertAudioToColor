import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var model = VoiceVisualizerViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                LiveAudioChart(points: model.chartPoints, color: currentColor)
                    .frame(height: 220)
                controls
            }
            .padding(24)
        }
        .background(Color.black.ignoresSafeArea())
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
                Text("noise \(model.features.noiseLevel, specifier: "%.2f")")
                Spacer()
                if model.hasReplay {
                    Text("Replay available").foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if let summary = model.summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION SUMMARY")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                    Text(summary.description)
                    Text("duration \(summary.duration, specifier: "%.1fs") · avg arousal \(summary.averageArousal, specifier: "%.2f")")
                    Text(summary.emotionalConclusion)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Ini interpretasi karakter akustik suara, bukan diagnosis emosi.")
                        .font(.caption2)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
            }
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

    private var currentColor: Color {
        Color(hue: model.visual.hue,
              saturation: model.visual.saturation,
              brightness: model.visual.brightness)
    }
}

struct LiveAudioChart: View {
    let points: [AudioChartPoint]
    let color: Color

    var body: some View {
        Group {
            if points.isEmpty {
                ContentUnavailableView("No audio yet", systemImage: "waveform")
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("Time", point.id), y: .value("Level", point.level))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.60), color.opacity(0.04)],
                                                         startPoint: .top, endPoint: .bottom))

                    LineMark(x: .value("Time", point.id), y: .value("Level", point.level))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    LineMark(x: .value("Time", point.id), y: .value("Frequency", point.frequency))
                        .foregroundStyle(color.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
            }
        }
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            Text("LIVE AUDIO")
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .animation(.linear(duration: 0.08), value: points)
    }

    private var xDomain: ClosedRange<Int> {
        guard let first = points.first?.id, let last = points.last?.id else { return 0...1 }
        return first == last ? first...(last + 1) : first...last
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
