import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = HexDocumentModel()
    @State private var isDropTargeted = false
    @State private var hexEditorDraft = ""
    @State private var textEditorDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.25)
            content
            Divider().opacity(0.25)
            statusBar
        }
        .background(Color(red: 0.16, green: 0.17, blue: 0.22))
        .frame(minWidth: 1120, minHeight: 760)
        .preferredColorScheme(.dark)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if $0 == false { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: model.selectionSnapshotKey) {
            syncSelectionEditors()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: loadDroppedProviders)
        .onAppear {
            syncSelectionEditors()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            Button(action: openFile) {
                Label(model.hasFile ? "Open Another File" : "Choose File…", systemImage: "doc.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.47, green: 0.49, blue: 0.61))
            .keyboardShortcut("o")

            pathBar

            Spacer(minLength: 0)

            if model.hasFile {
                Picker("View", selection: $model.activeTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Button("Save") {
                    model.saveFile()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("s")

                Button("Revert") {
                    model.revertChanges()
                }
                .buttonStyle(.bordered)
                .disabled(model.isDirty == false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.18, green: 0.19, blue: 0.25))
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.hasFile ? "doc.richtext.fill" : "doc")
                .foregroundStyle(Color.white.opacity(0.86))
                .font(.system(size: 18, weight: .semibold))

            if model.hasFile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.breadcrumbItems.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }

                            Text(item)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.82))
                        }
                    }
                }
            } else {
                Text("Drop a file or application here, or use Choose File.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if model.hasFile {
            Group {
                switch model.activeTab {
                case .info:
                    infoPane
                case .editor:
                    editorPane
                }
            }
            .padding(20)
        } else {
            EmptyStateView(isDropTargeted: isDropTargeted, chooseAction: openFile)
                .padding(32)
        }
    }

    private var infoPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailCard {
                DetailRow(label: "Kind", value: model.metadata.kindDescription)
                DetailRow(label: "Size", value: model.metadata.sizeDescription)
                DetailRow(label: "Resolved URL", value: model.metadata.resolvedURL?.path ?? "—")
                DetailRow(label: "Owner", value: model.metadata.owner)
                DetailRow(label: "Group", value: model.metadata.group)
                DetailRow(label: "Created", value: model.metadata.created)
                DetailRow(label: "Modified", value: model.metadata.modified)
            }

            detailCard {
                CopyableHashRow(label: "MD5", value: model.hashes.md5) {
                    model.copyHash(model.hashes.md5, label: "MD5 hash")
                }

                CopyableHashRow(label: "SHA1", value: model.hashes.sha1) {
                    model.copyHash(model.hashes.sha1, label: "SHA1 hash")
                }

                CopyableHashRow(label: "SHA256", value: model.hashes.sha256) {
                    model.copyHash(model.hashes.sha256, label: "SHA256 hash")
                }
            }

            detailCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Base64")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    Text(model.base64IsReady ? "Ready to copy or export." : "Generated on demand to keep the editor lightweight.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.68))

                    HStack(spacing: 10) {
                        Button("Copy") {
                            model.copyBase64()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Save…") {
                            model.exportBase64()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var editorPane: some View {
        VStack(spacing: 16) {
            searchCard

            detailCard(padding: 12) {
                HexDocumentEditorView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            selectionCard
        }
    }

    private var searchCard: some View {
        detailCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Interpretation", selection: $model.searchMode) {
                        ForEach(SearchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)

                    LabeledField(label: "Find", text: $model.findQuery, placeholder: model.searchMode == .hex ? "89 50 4E 47" : "Search text")
                    LabeledField(label: "Replace", text: $model.replaceQuery, placeholder: model.searchMode == .hex ? "FF D8 FF E0" : "Replacement text")
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button("Replace All") {
                        model.replaceAllMatches()
                    }
                    .buttonStyle(.bordered)

                    Button("Replace") {
                        model.replaceCurrentMatch()
                    }
                    .buttonStyle(.bordered)

                    Button("Replace & Find") {
                        model.replaceCurrentAndFindNext()
                    }
                    .buttonStyle(.bordered)

                    Button("Previous") {
                        model.findPrevious()
                    }
                    .buttonStyle(.bordered)

                    Button("Next") {
                        model.findNext()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var selectionCard: some View {
        detailCard {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Text(model.selectionDescription)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.88))

                    Spacer(minLength: 0)

                    Text("Length")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Stepper(value: $model.selectionLength, in: 1...max(model.dataCount, 1)) {
                        Text("\(max(model.selectionLength, 0))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .labelsHidden()

                    TextField("0x0", text: $model.jumpQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 120)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Move") {
                        model.moveSelection()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Text("Direct edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: 88, alignment: .leading)

                    Text("Drag-select in either pane, then type, paste, or copy just like a text editor. The helper fields below still work for larger replacements.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    LabeledField(label: "Hex", text: $hexEditorDraft, placeholder: "4F 70 65 6E")

                    Button("Apply Hex") {
                        model.applyHexEdit(hexEditorDraft)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    LabeledField(label: "Text", text: $textEditorDraft, placeholder: "Editable UTF-8 text")

                    Button("Apply Text") {
                        model.applyTextEdit(textEditorDraft)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button("Export Hex…") {
                        model.exportHexDump()
                    }
                    .buttonStyle(.bordered)

                    Button("Export Text…") {
                        model.exportTextPreview()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            Text(model.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(2)

            Spacer(minLength: 0)

            if model.hasFile {
                Text(model.windowTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14))
    }

    private func detailCard<Content: View>(padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func syncSelectionEditors() {
        hexEditorDraft = model.selectedHexText
        textEditorDraft = model.selectedTextText
    }

    private func openFile() {
        if let url = AppKitPanels.chooseSourceURL() {
            model.openFile(at: url)
        }
    }

    private func loadDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolvedURL: URL?

            if let data = item as? Data {
                resolvedURL = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL
            } else if let string = item as? String {
                resolvedURL = URL(string: string)
            } else if let url = item as? URL {
                resolvedURL = url
            }

            guard let resolvedURL else { return }

            DispatchQueue.main.async {
                model.openFile(at: resolvedURL)
            }
        }

        return true
    }
}

private struct EmptyStateView: View {
    let isDropTargeted: Bool
    let chooseAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                )
                .foregroundStyle(isDropTargeted ? Color.white.opacity(0.82) : Color.white.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(isDropTargeted ? 0.08 : 0.03))
                )
                .overlay {
                    VStack(spacing: 20) {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.white.opacity(0.86))

                        Text("Drop a file or application here.")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.95))

                        Text("Choose a file below if you’d rather browse manually.")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                    }
                    .padding(36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("Choose File…", action: chooseAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.47, green: 0.49, blue: 0.61))
                .controlSize(.large)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct CopyableHashRow: View {
    let label: String
    let value: String
    let copyAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Button("Copy", action: copyAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 54, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

private struct CellFocus: Hashable {
    let mode: ByteEditorMode
    let offset: Int
}

private struct HexGridView: View {
    @ObservedObject var model: HexDocumentModel
    @State private var focusedCell: CellFocus?

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider().overlay(Color.white.opacity(0.08))

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(0..<model.rowCount, id: \.self) { rowIndex in
                            HexRowView(
                                row: model.row(at: rowIndex),
                                dataCount: max(model.dataCount, 1),
                                model: model,
                                focusedCell: $focusedCell
                            )
                            .id(rowIndex)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.1))
                .onChange(of: model.selectionStart) {
                    if let selectionStart = model.selectionStart {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(selectionStart / HexTools.bytesPerRow, anchor: .center)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Offset")
                .frame(width: 92, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<HexTools.bytesPerRow, id: \.self) { value in
                    Text(String(format: "%02X", value))
                        .frame(width: 28)
                }
            }
            .frame(width: 28 * CGFloat(HexTools.bytesPerRow) + 4 * CGFloat(HexTools.bytesPerRow - 1), alignment: .leading)

            Text("ASCII")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.72))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }

}

private struct HexRowView: View {
    let row: HexEditorRow
    let dataCount: Int
    @ObservedObject var model: HexDocumentModel
    @Binding var focusedCell: CellFocus?

    var body: some View {
        HStack(spacing: 0) {
            Text(HexTools.formatOffset(row.baseOffset, dataCount: dataCount))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: 92, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<HexTools.bytesPerRow, id: \.self) { column in
                    let offset = row.baseOffset + column

                    if column < row.bytes.count {
                        EditableByteCell(
                            mode: .hex,
                            offset: offset,
                            width: 28,
                            model: model,
                            focusedCell: $focusedCell
                        )
                    } else {
                        Text("  ")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.clear)
                            .frame(width: 28, height: 24)
                    }
                }
            }

            HStack(spacing: 2) {
                ForEach(0..<HexTools.bytesPerRow, id: \.self) { column in
                    let offset = row.baseOffset + column

                    if column < row.bytes.count {
                        EditableByteCell(
                            mode: .text,
                            offset: offset,
                            width: 14,
                            model: model,
                            focusedCell: $focusedCell
                        )
                    } else {
                        Text(" ")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.clear)
                            .frame(width: 14, height: 24)
                    }
                }
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(row.index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.white.opacity(0.055))
        )
    }
}

private struct EditableByteCell: View {
    let mode: ByteEditorMode
    let offset: Int
    var width: CGFloat
    @ObservedObject var model: HexDocumentModel
    @Binding var focusedCell: CellFocus?
    @State private var draft = ""

    private var focusID: CellFocus {
        CellFocus(mode: mode, offset: offset)
    }

    private var isSelected: Bool {
        model.isSelected(offset: offset)
    }

    private var replacementLength: Int {
        model.selectionStart == offset ? max(model.selectionLength, 1) : 1
    }

    var body: some View {
        SelectableByteTextField(
            text: $draft,
            isFocused: focusedCell == focusID,
            width: width,
            onActivate: {
                focusedCell = focusID
                model.selectRange(start: offset)
            },
            onCopy: {
                model.copySelection(using: mode)
            },
            onTextChange: handleDraftChange,
            onEditingEnded: syncDraftFromModel
        )
        .frame(width: width, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color(red: 0.88, green: 0.90, blue: 0.97) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    focusedCell == focusID
                    ? Color.white.opacity(0.35)
                    : Color.clear,
                    lineWidth: 1
                )
        )
        .onAppear(perform: syncDraftFromModel)
        .onChange(of: model.selectionRefreshToken) {
            if focusedCell != focusID {
                syncDraftFromModel()
            }
        }
    }

    private func syncDraftFromModel() {
        draft = switch mode {
        case .hex:
            model.hexValue(at: offset)
        case .text:
            model.textValue(at: offset)
        }
    }

    private func handleDraftChange(_ newValue: String) {
        model.selectRange(start: offset)

        switch mode {
        case .hex:
            let filtered = newValue
                .uppercased()
                .filter(\.isHexDigit)

            if filtered != newValue {
                draft = filtered
                return
            }

            guard filtered.isEmpty == false, filtered.count.isMultiple(of: 2) else {
                return
            }

            if let written = model.replaceHexInput(filtered, at: offset, replacing: replacementLength) {
                syncDraftFromModel()
                advanceFocus(by: written)
            }
        case .text:
            guard newValue.isEmpty == false else {
                return
            }

            if let written = model.replaceTextInput(newValue, at: offset, replacing: replacementLength) {
                syncDraftFromModel()
                advanceFocus(by: written)
            }
        }
    }

    private func advanceFocus(by bytesWritten: Int) {
        guard model.dataCount > 0 else {
            focusedCell = nil
            return
        }

        let nextOffset = min(offset + max(bytesWritten, 1), model.dataCount - 1)
        focusedCell = CellFocus(mode: mode, offset: nextOffset)
        model.selectRange(start: nextOffset)
    }
}

private struct SelectableByteTextField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let width: CGFloat
    let onActivate: () -> Void
    let onCopy: () -> Void
    let onTextChange: (String) -> Void
    let onEditingEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ActivatingByteTextField {
        let field = ActivatingByteTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.alignment = .center
        field.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        field.textColor = .white
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.translatesAutoresizingMaskIntoConstraints = false
        field.onActivate = onActivate
        field.onCopy = onCopy
        return field
    }

    func updateNSView(_ nsView: ActivatingByteTextField, context: Context) {
        context.coordinator.parent = self
        nsView.onActivate = onActivate
        nsView.onCopy = onCopy

        if (nsView.currentEditor() == nil || isFocused == false), nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isFocused, nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                guard nsView.window != nil else { return }
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectedRange = NSRange(location: 0, length: (nsView.stringValue as NSString).length)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectableByteTextField

        init(_ parent: SelectableByteTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onActivate()
            guard let field = obj.object as? NSTextField else { return }
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (field.stringValue as NSString).length)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            if parent.text != value {
                parent.text = value
            }
            parent.onTextChange(value)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onEditingEnded()
        }
    }
}

private final class ActivatingByteTextField: NSTextField {
    var onActivate: (() -> Void)?
    var onCopy: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async {
                self.currentEditor()?.selectedRange = NSRange(location: 0, length: (self.stringValue as NSString).length)
            }
        }
        return result
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           let onCopy
        {
            onCopy()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

#Preview {
    ContentView()
}
