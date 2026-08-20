import SwiftUI

struct ToolPaletteView: View {
    @Binding var selectedTool: AnnotationTool

    private let groups: [[AnnotationTool]] = [
        [.select],
        [.pencil, .pen, .highlighter],
        [.arrow, .line, .rectangle, .ellipse],
        [.text],
        [.blur, .pixelate]
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 7) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, tools in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 3)
                            .padding(.horizontal, 9)
                    }

                    ForEach(tools) { tool in
                        toolButton(tool)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 7)
        }
        .frame(width: 58)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(width: 1)
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ToolButtonStyle(isSelected: selectedTool == tool))
        .help("\(tool.displayName)  \(tool.keyboardHint)")
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
    }
}

private struct ToolButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

extension AnnotationTool {
    var keyboardHint: String {
        switch self {
        case .select: return "V"
        case .pencil: return "P"
        case .pen: return "B"
        case .highlighter: return "H"
        case .arrow: return "A"
        case .line: return "L"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .text: return "T"
        case .blur: return "U"
        case .pixelate: return "M"
        }
    }
}
