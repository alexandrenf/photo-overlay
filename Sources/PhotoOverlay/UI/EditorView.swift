import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject private var coordinator: AppCoordinator
    @ObservedObject private var document: EditorDocument
    @ObservedObject private var viewportState: CanvasViewportState

    @State private var isInspectorVisible = true
    @State private var isCropping = false
    @State private var cropSelection: PixelRect?
    @State private var isDropTargeted = false
    @State private var showsShortcutHelp = false
    @State private var showsClearConfirmation = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _document = ObservedObject(wrappedValue: coordinator.document)
        _viewportState = ObservedObject(wrappedValue: coordinator.viewportState)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                editorToolbar
                Divider()

                if document.hasImage {
                    editorWorkspace
                    Divider()
                    statusBar
                } else {
                    emptyState
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))

            if let toast = coordinator.toast {
                ToastView(toast: toast)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if isDropTargeted {
                dropOverlay
                    .transition(.opacity)
                    .zIndex(9)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: coordinator.toast)
        .animation(.easeOut(duration: 0.18), value: isDropTargeted)
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isDropTargeted,
            perform: coordinator.handleDrop
        )
        .alert(
            "Overlay couldn’t complete that",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                coordinator.errorMessage = nil
            }
        } message: {
            Text(coordinator.errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Remove every annotation?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Annotations", role: .destructive) {
                document.clearAnnotations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original image will be kept, and this can be undone.")
        }
        .sheet(isPresented: $showsShortcutHelp) {
            KeyboardShortcutsView()
        }
    }

    private var editorToolbar: some View {
        ZStack {
            WindowDragRegion()

            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Overlay")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .padding(.leading, 76)

                if document.hasImage {
                    Text("\(Int(document.imageSize.width)) × \(Int(document.imageSize.height))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)

                toolbarButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: document.canUndo) {
                    document.undo()
                }
                .keyboardShortcut("z", modifiers: .command)

                toolbarButton("Redo", systemImage: "arrow.uturn.forward", isEnabled: document.canRedo) {
                    document.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                if document.hasImage {
                    toolbarButton("Crop", systemImage: isCropping ? "crop.rotate" : "crop", isSelected: isCropping) {
                        toggleCrop()
                    }

                    Menu {
                        Button("Rotate Left", systemImage: "rotate.left") {
                            transformImage { try document.rotateCounterclockwise() }
                        }
                        Button("Rotate Right", systemImage: "rotate.right") {
                            transformImage { try document.rotateClockwise() }
                        }
                        Divider()
                        Button("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                            transformImage { try document.flipHorizontal() }
                        }
                        Button("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                            transformImage { try document.flipVertical() }
                        }
                    } label: {
                        Image(systemName: "rotate.right")
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 30)
                    .help("Rotate and flip")
                }

                Spacer(minLength: 8)

                if let selected = document.selectedAnnotation {
                    Text(selected.tool.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    toolbarButton("Duplicate", systemImage: "plus.square.on.square") {
                        document.duplicateSelectedAnnotation()
                    }
                    toolbarButton("Delete", systemImage: "trash") {
                        document.removeSelectedAnnotation()
                    }
                }

                if document.hasImage {
                    toolbarButton(
                        isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.right",
                        isSelected: isInspectorVisible
                    ) {
                        isInspectorVisible.toggle()
                    }

                    Button {
                        coordinator.copyResult()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("c", modifiers: .command)

                    Button {
                        coordinator.saveResult()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Save…  ⌘S")
                    .keyboardShortcut("s", modifiers: .command)
                }

                Button("Done") {
                    coordinator.hideEditor()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.trailing, 12)
            }
            .frame(height: 50)
        }
        .frame(height: 50)
        .background(.ultraThinMaterial)
    }

    private var editorWorkspace: some View {
        HStack(spacing: 0) {
            ToolPaletteView(selectedTool: activeToolBinding)
                .disabled(isCropping)

            ZStack(alignment: .bottom) {
                EditorCanvasView(
                    document: document,
                    viewportState: viewportState,
                    isCropping: isCropping,
                    cropSelection: $cropSelection,
                    onSave: coordinator.saveResult,
                    onCopy: coordinator.copyResult,
                    onDismiss: coordinator.hideEditor,
                    onError: coordinator.present
                )

                if isCropping {
                    cropActionBar
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()

            if isInspectorVisible && !isCropping {
                StyleInspectorView(
                    tool: inspectorTool,
                    style: inspectorStyleBinding,
                    onContinuousEditingChanged: handleInspectorContinuousEditing
                )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isInspectorVisible)
        .animation(.easeInOut(duration: 0.18), value: isCropping)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(
                "\(document.annotations.count) \(document.annotations.count == 1 ? "annotation" : "annotations")",
                systemImage: "square.3.layers.3d"
            )
            .foregroundStyle(.secondary)

            if !document.annotations.isEmpty {
                Button("Clear") {
                    showsClearConfirmation = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showsShortcutHelp = true
            } label: {
                Label("Shortcuts", systemImage: "command")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider().frame(height: 14)

            Button {
                viewportState.zoom = max(0.2, viewportState.zoom / 1.2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom out  ⌘−")

            Button(viewportState.zoomLabel) {
                viewportState.reset()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .frame(width: 45)
            .help("Fit image  ⌘0")

            Button {
                viewportState.zoom = min(8, viewportState.zoom * 1.2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom in  ⌘+")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 112, height: 112)
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 7) {
                Text("Copy. Mark up. Share.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Copy any screenshot or photo, then open it here instantly.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    coordinator.openClipboard()
                } label: {
                    Label("Open Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    coordinator.openFilePicker()
                } label: {
                    Label("Choose Image…", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            HStack(spacing: 6) {
                Text("Global shortcut")
                KeyCap("⌘")
                KeyCap("⇧")
                KeyCap("2")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Text("You can also drop an image anywhere in this window.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.035), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var cropActionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "crop")
                .foregroundStyle(.secondary)
            if let cropSelection {
                Text("\(Int(cropSelection.width.rounded())) × \(Int(cropSelection.height.rounded()))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            } else {
                Text("Drag to choose the crop")
                    .font(.callout)
            }

            Divider().frame(height: 18)

            Button("Cancel") {
                cancelCrop()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                applyCrop()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(cropSelection?.isEmpty != false)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .padding(12)
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 40, weight: .medium))
                    Text("Drop to edit")
                        .font(.title2.bold())
                }
                .foregroundStyle(Color.accentColor)
            }
            .padding(14)
    }

    private var activeToolBinding: Binding<AnnotationTool> {
        Binding(
            get: { document.activeTool },
            set: { newTool in
                let oldColor = document.style.strokeColor
                var nextStyle = AnnotationStyle.default(for: newTool)
                if newTool.acceptsColor && document.activeTool.acceptsColor {
                    nextStyle.strokeColor = oldColor
                }
                document.style = nextStyle
                document.selectTool(newTool)
            }
        )
    }

    private var inspectorTool: AnnotationTool {
        if document.activeTool == .select, let selected = document.selectedAnnotation {
            return selected.tool
        }
        return document.activeTool
    }

    private var inspectorStyleBinding: Binding<AnnotationStyle> {
        Binding(
            get: {
                if document.activeTool == .select, let selected = document.selectedAnnotation {
                    return selected.style
                }
                return document.style
            },
            set: { newStyle in
                if document.activeTool == .select, let id = document.selectedAnnotationID {
                    document.updateAnnotation(id: id) { annotation in
                        annotation.style = newStyle
                    }
                } else {
                    document.style = newStyle
                }
            }
        )
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? (isSelected ? Color.accentColor : Color.primary) : Color.secondary.opacity(0.45))
        .disabled(!isEnabled)
        .help(title)
    }

    private func toggleCrop() {
        isCropping.toggle()
        cropSelection = nil
        document.cancelDraft()
        document.select(nil)
    }

    private func cancelCrop() {
        cropSelection = nil
        isCropping = false
    }

    private func applyCrop() {
        guard let cropSelection else { return }
        do {
            try document.crop(to: cropSelection)
            isCropping = false
            self.cropSelection = nil
            viewportState.reset()
            coordinator.showToast("Crop applied", systemImage: "crop", tone: .success)
        } catch {
            coordinator.present(error)
        }
    }

    private func transformImage(_ operation: () throws -> Void) {
        do {
            try operation()
            viewportState.reset()
            coordinator.showToast("Image transformed", systemImage: "rotate.right", tone: .success)
        } catch {
            coordinator.present(error)
        }
    }

    private func handleInspectorContinuousEditing(_ isEditing: Bool) {
        guard document.activeTool == .select, document.selectedAnnotationID != nil else { return }
        if isEditing {
            document.beginEditingTransaction()
        } else {
            document.endEditingTransaction()
        }
    }
}

private struct ToastView: View {
    let toast: AppCoordinator.Toast

    var body: some View {
        Label(toast.text, systemImage: toast.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.ultraThickMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private var tint: Color {
        switch toast.tone {
        case .neutral: return .accentColor
        case .success: return .green
        case .error: return .red
        }
    }
}

private struct KeyCap: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 22, minHeight: 20)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private extension AnnotationTool {
    var acceptsColor: Bool {
        switch self {
        case .select, .blur, .pixelate: return false
        default: return true
        }
    }
}
