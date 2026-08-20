import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private let actionShortcuts: [(String, String)] = [
        ("Open clipboard from anywhere", "⌘ ⇧ 2"),
        ("Undo / redo", "⌘ Z / ⇧ ⌘ Z"),
        ("Copy result", "⌘ C"),
        ("Save", "⌘ S"),
        ("Fit image", "⌘ 0"),
        ("Zoom", "⌘ + / ⌘ −"),
        ("Duplicate selection", "⌘ D"),
        ("Delete selection", "⌫"),
        ("Pan", "Space + drag"),
        ("Close overlay", "Esc")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard shortcuts")
                        .font(.title2.bold())
                    Text("Everything important stays one keystroke away.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Divider()

            HStack(alignment: .top, spacing: 34) {
                shortcutColumn("TOOLS", rows: AnnotationTool.allCases.map { ($0.displayName, $0.keyboardHint) })
                shortcutColumn("ACTIONS", rows: actionShortcuts)
            }
            .padding(22)
        }
        .frame(width: 570, height: 470)
        .background(.regularMaterial)
    }

    private func shortcutColumn(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
                .padding(.bottom, 8)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 32)

                if row.0 != rows.last?.0 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
