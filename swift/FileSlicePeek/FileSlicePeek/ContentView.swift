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
            Divider()
            content
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1180, minHeight: 820)
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
                .buttonStyle(.borderedProminent)
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
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.hasFile ? "doc.richtext.fill" : "doc")
                .foregroundStyle(.secondary)
                .font(.system(size: 18, weight: .semibold))

            if model.hasFile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.breadcrumbItems.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }

                            Text(item)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } else {
                Text("Drop a file or application here, or use Choose File.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
                        .foregroundStyle(.primary)

                    Text(model.base64IsReady ? "Ready to copy or export." : "Generated on demand to keep the app lightweight.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

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
                    .frame(minHeight: 520)
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
                    .frame(width: 150)

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
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("Length")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Stepper(value: $model.selectionLength, in: 0...max(model.dataCount, 0)) {
                        Text("\(max(model.selectionLength, 0))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 54, alignment: .trailing)
                    }
                    .labelsHidden()

                    TextField("0x0", text: $model.jumpQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 120)

                    Button("Move") {
                        model.moveSelection()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Text("Direct edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)

                    Text("Click or drag in the hex or text pane, then type or paste directly. The helper fields below are for deliberate range replacements.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

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
                    LabeledField(label: "Text", text: $textEditorDraft, placeholder: "ASCII replacement")

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
            }

            Text(model.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if model.hasFile {
                Text(model.windowTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func detailCard<Content: View>(padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
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
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    VStack(spacing: 20) {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.accentColor)

                        Text("Drop a file or application here.")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("Choose a file below if you’d rather browse manually.")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("Choose File…", action: chooseAction)
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
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
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
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
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}
