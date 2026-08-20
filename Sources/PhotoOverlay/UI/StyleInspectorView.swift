import AppKit
import SwiftUI

struct StyleInspectorView: View {
    let tool: AnnotationTool
    @Binding var style: AnnotationStyle
    var onContinuousEditingChanged: (Bool) -> Void = { _ in }

    private let swatches: [RGBAColor] = [
        .red, .orange, .yellow, .green, .blue, .purple, .white, .black
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: tool.systemImage)
                    .foregroundStyle(.secondary)
                Text(tool.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(tool.keyboardHint)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }

            if tool.usesStrokeColor {
                inspectorSection("COLOR") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 8) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                            swatch(color)
                        }

                        ColorPicker("Custom color", selection: strokeColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                            .help("Custom color")
                    }
                }
            }

            switch tool {
            case .pencil, .pen, .highlighter, .arrow, .line, .rectangle, .ellipse:
                inspectorSection("STROKE") {
                    valueSlider(
                        value: $style.lineWidth,
                        range: tool == .highlighter ? 6 ... 64 : 1 ... 32,
                        suffix: "pt"
                    )

                    Toggle("Dashed", isOn: dashedBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if tool == .rectangle || tool == .ellipse {
                    inspectorSection("FILL") {
                        Toggle("Add fill", isOn: fillEnabledBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        if style.fillColor != nil {
                            valueSlider(value: fillOpacityBinding, range: 0.05 ... 1, suffix: "%", percentage: true)
                        }
                    }
                }

                if tool == .rectangle {
                    inspectorSection("CORNERS") {
                        valueSlider(value: $style.cornerRadius, range: 0 ... 80, suffix: "pt")
                    }
                }

            case .text:
                inspectorSection("TYPE") {
                    valueSlider(value: $style.fontSize, range: 10 ... 120, suffix: "pt")

                    Picker("Weight", selection: $style.fontWeight) {
                        ForEach(AnnotationFontWeight.allCases, id: \.self) { weight in
                            Text(weight.label).tag(weight)
                        }
                    }
                    .pickerStyle(.menu)
                }

                inspectorSection("BACKGROUND") {
                    Toggle("Text backing", isOn: fillEnabledBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if style.fillColor != nil {
                        valueSlider(value: fillOpacityBinding, range: 0.05 ... 1, suffix: "%", percentage: true)
                    }
                }

            case .blur:
                inspectorSection("STRENGTH") {
                    valueSlider(value: $style.blurRadius, range: 4 ... 64, suffix: "pt")
                    Text("Drag over anything sensitive. The effect stays editable until export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .pixelate:
                inspectorSection("BLOCK SIZE") {
                    valueSlider(value: $style.pixelScale, range: 4 ... 48, suffix: "px")
                    Text("Use larger blocks to make names and identifiers unreadable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .select:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Click an annotation to move or remove it.", systemImage: "cursorarrow.click.2")
                    Label("Drag on empty canvas to pan while zoomed.", systemImage: "hand.draw")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if tool.usesOpacity {
                inspectorSection("OPACITY") {
                    valueSlider(value: $style.opacity, range: 0.1 ... 1, suffix: "%", percentage: true)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(width: 224)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(width: 1)
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            content()
        }
    }

    private func swatch(_ color: RGBAColor) -> some View {
        let isSelected = style.strokeColor == color
        return Button {
            style.strokeColor = color
        } label: {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.18), lineWidth: isSelected ? 2.5 : 1)
                        .padding(isSelected ? -3 : 0)
                }
                .overlay {
                    if color == .white {
                        Circle().strokeBorder(.black.opacity(0.16), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("Use this color")
    }

    private func valueSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String,
        percentage: Bool = false
    ) -> some View {
        HStack(spacing: 9) {
            Slider(value: value, in: range, onEditingChanged: onContinuousEditingChanged)
            Text(formatted(value.wrappedValue, suffix: suffix, percentage: percentage))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func formatted(_ value: Double, suffix: String, percentage: Bool) -> String {
        percentage ? "\(Int((value * 100).rounded()))\(suffix)" : "\(Int(value.rounded()))\(suffix)"
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: style.strokeColor.nsColor) },
            set: { style.strokeColor = RGBAColor(NSColor($0)) }
        )
    }

    private var dashedBinding: Binding<Bool> {
        Binding(
            get: { !style.dashPattern.isEmpty },
            set: { style.dashPattern = $0 ? [10, 8] : [] }
        )
    }

    private var fillEnabledBinding: Binding<Bool> {
        Binding(
            get: { style.fillColor != nil },
            set: { enabled in
                if enabled {
                    style.fillColor = RGBAColor.black.withAlpha(tool == .text ? 0.62 : 0.18)
                } else {
                    style.fillColor = nil
                }
            }
        )
    }

    private var fillOpacityBinding: Binding<Double> {
        Binding(
            get: { style.fillColor?.alpha ?? 0.18 },
            set: { newValue in
                guard var fill = style.fillColor else { return }
                fill.alpha = newValue
                style.fillColor = fill
            }
        )
    }
}

private extension AnnotationTool {
    var usesStrokeColor: Bool {
        switch self {
        case .select, .blur, .pixelate: return false
        default: return true
        }
    }

    var usesOpacity: Bool {
        switch self {
        case .pencil, .pen, .highlighter, .arrow, .line, .rectangle, .ellipse: return true
        default: return false
        }
    }
}

private extension AnnotationFontWeight {
    var label: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }
}
