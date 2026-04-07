import AppKit
import Foundation

enum AppKitPanels {
    static func chooseSourceURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a file or application"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportURL(suggestedName: String, pathExtension: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.prompt = "Save"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = []
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if pathExtension.isEmpty == false {
            panel.allowedContentTypes = []
        }

        let result = panel.runModal() == .OK ? panel.url : nil

        guard let result else {
            return nil
        }

        if pathExtension.isEmpty || result.pathExtension.lowercased() == pathExtension.lowercased() {
            return result
        }

        return result.appendingPathExtension(pathExtension)
    }

    static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

