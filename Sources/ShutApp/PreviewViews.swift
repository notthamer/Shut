import SwiftUI
import TransitionKit

/// Aspect ratio of the built-in display, so the preview matches the real screen.
enum BuiltInDisplayAspect {
    static var ratio: CGFloat {
        guard let f = BuiltInDisplay.screen?.frame, f.height > 0 else { return 16.0 / 10.0 }
        return f.width / f.height
    }
}

/// Hosts the Metal preview view inside SwiftUI.
struct PreviewMetalView: NSViewRepresentable {
    @ObservedObject var model: PreviewModel

    func makeNSView(context: Context) -> MetalTransitionView {
        let view = MetalTransitionView(renderer: model.renderer, transition: model.registry.current, context: model.context)
        model.metalView = view
        return view
    }

    func updateNSView(_ view: MetalTransitionView, context: Context) {
        model.render()
    }
}

/// The preview area: snapshot with transport controls. Used in the standalone
/// preview window and, from M3, inside Tuner's preview slot.
struct PreviewArea: View {
    @ObservedObject var model: PreviewModel
    @ObservedObject var registry: TransitionRegistry
    var aspect: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                PreviewMetalView(model: model)
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if !model.hasSnapshot {
                    VStack(spacing: 8) {
                        if model.isCapturing {
                            ProgressView()
                        } else {
                            Text(model.errorText ?? "No snapshot yet")
                                .foregroundStyle(.secondary)
                            Button("Capture desktop") { model.capture() }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { registry.current.id },
                    set: { registry.select(id: $0) }
                )) {
                    ForEach(registry.all, id: \.id) { t in Text(t.displayName).tag(t.id) }
                }
                .labelsHidden()
                .frame(width: 130)

                Button("Play close") { model.playClose() }
                Button("Play pour-out") { model.playPourOut() }
                Button {
                    model.capture()
                } label: { Image(systemName: "camera") }
                .help("Re-capture the desktop")
                Spacer()
                Toggle("Follow lid", isOn: $model.followLid)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack {
                Text("Progress")
                Slider(value: $model.progress, in: -0.15...1)
                Text(String(format: "%.2f", model.progress)).monospacedDigit().frame(width: 40)
            }
            .disabled(model.followLid)

            HStack {
                Text(String(format: "frame %.2f ms", model.frameTimeMs))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if let error = model.errorText, model.hasSnapshot {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
