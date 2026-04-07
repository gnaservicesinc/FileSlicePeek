import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1220
    height: 820
    visible: true
    title: backend.hasFile ? backend.displayName + (backend.dirty ? " *" : "") : "FileSlicePeek"
    color: "#2b2c36"

    property int exportMode: 0
    property bool dragActive: false
    property int focusedOffset: -1
    property string focusedMode: "hex"

    QtObject {
        id: theme
        readonly property color background: "#2b2c36"
        readonly property color panel: "#303241"
        readonly property color panelAlt: "#3a3d50"
        readonly property color border: "#51556a"
        readonly property color text: "#f2f4ff"
        readonly property color muted: "#b5b8cc"
        readonly property color accent: "#d8def4"
        readonly property color accentText: "#151822"
    }

    header: ToolBar {
        padding: 12
        background: Rectangle { color: "#303241" }

        contentItem: RowLayout {
            spacing: 12

            Button {
                text: backend.hasFile ? "Open Another File" : "Choose File"
                onClicked: openDialog.open()
            }

            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 12
                color: "#3a3d50"
                border.color: theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label {
                        text: backend.hasFile ? "File" : "Ready"
                        color: theme.text
                        font.bold: true
                    }

                    Label {
                        Layout.fillWidth: true
                        text: backend.hasFile ? backend.visiblePath : "Drop a file or application here, or use Choose File."
                        color: theme.muted
                        elide: Text.ElideMiddle
                    }
                }
            }

            Button {
                text: "Save"
                enabled: backend.hasFile
                onClicked: backend.save()
            }

            Button {
                text: "Revert"
                enabled: backend.dirty
                onClicked: backend.revert()
            }
        }
    }

    footer: Rectangle {
        color: "#23242d"
        implicitHeight: 38

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            BusyIndicator {
                running: backend.loading
                visible: running
            }

            Label {
                Layout.fillWidth: true
                text: backend.statusText
                color: theme.muted
                elide: Text.ElideRight
            }

            Label {
                text: backend.hasFile ? backend.displayName : ""
                color: theme.muted
                font.bold: true
            }
        }
    }

    FileDialog {
        id: openDialog
        title: "Choose a file or application"
        fileMode: FileDialog.OpenFile
        onAccepted: backend.openFile(selectedFile)
    }

    FileDialog {
        id: exportDialog
        title: "Export"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            if (window.exportMode === 1) {
                backend.exportHex(selectedFile)
            } else if (window.exportMode === 2) {
                backend.exportText(selectedFile)
            } else if (window.exportMode === 3) {
                backend.exportBase64(selectedFile)
            }
        }
    }

    Dialog {
        id: errorDialog
        title: "Something went wrong"
        visible: backend.errorMessage.length > 0
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Ok
        onAccepted: backend.clearError()

        contentItem: Label {
            text: backend.errorMessage
            color: theme.text
            wrapMode: Text.WordWrap
        }

        background: Rectangle {
            radius: 12
            color: theme.panel
            border.color: theme.border
        }
    }

    DropArea {
        anchors.fill: parent
        onEntered: window.dragActive = true
        onExited: window.dragActive = false
        onDropped: (drop) => {
            window.dragActive = false
            if (drop.urls.length > 0) {
                backend.openFile(drop.urls[0])
            }
        }
    }

    SwipeView {
        id: pages
        anchors.fill: parent
        anchors.margins: 20
        currentIndex: tabs.currentIndex
        interactive: false
        visible: backend.hasFile

        Pane {
            padding: 18
            background: Rectangle {
                radius: 16
                color: theme.panel
                border.color: theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        DetailRow { label: "Kind"; value: backend.kindDescription }
                        DetailRow { label: "Size"; value: backend.sizeDescription }
                        DetailRow { label: "Owner"; value: backend.ownerName }
                        DetailRow { label: "Group"; value: backend.groupName }
                        DetailRow { label: "Created"; value: backend.createdText }
                        DetailRow { label: "Modified"; value: backend.modifiedText }
                    }
                }

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        HashRow { label: "MD5"; value: backend.md5Hash }
                        HashRow { label: "SHA1"; value: backend.sha1Hash }
                        HashRow { label: "SHA256"; value: backend.sha256Hash }
                    }
                }

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Label {
                            text: "Base64"
                            color: theme.text
                            font.bold: true
                        }

                        Label {
                            text: backend.base64Ready ? "Ready to copy or save." : "Generated on demand to keep the app lightweight."
                            color: theme.muted
                        }

                        RowLayout {
                            spacing: 10
                            Button { text: "Copy"; onClicked: backend.copyBase64() }
                            Button {
                                text: "Save…"
                                onClicked: {
                                    window.exportMode = 3
                                    exportDialog.open()
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Pane {
            padding: 18
            background: Rectangle {
                radius: 16
                color: theme.panel
                border.color: theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 14

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        RowLayout {
                            spacing: 10

                            ComboBox {
                                model: ["hex", "text"]
                                currentIndex: backend.searchMode === "text" ? 1 : 0
                                onActivated: backend.searchMode = currentText
                                Layout.preferredWidth: 110
                            }

                            LabeledTextField {
                                label: "Find"
                                text: backend.findQuery
                                placeholderText: backend.searchMode === "hex" ? "89 50 4E 47" : "Search text"
                                onFieldEdited: backend.findQuery = value
                                Layout.fillWidth: true
                            }

                            LabeledTextField {
                                label: "Replace"
                                text: backend.replaceQuery
                                placeholderText: backend.searchMode === "hex" ? "FF D8 FF E0" : "Replacement text"
                                onFieldEdited: backend.replaceQuery = value
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 10

                            Button { text: "Replace All"; onClicked: backend.replaceAll() }
                            Button { text: "Replace"; onClicked: backend.replaceOne() }
                            Button { text: "Replace & Find"; onClicked: backend.replaceOneAndFind() }
                            Button { text: "Previous"; onClicked: backend.findPrevious() }
                            Button { text: "Next"; onClicked: backend.findNext() }
                        }
                    }
                }

                Frame {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: 0
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: "#42465a"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 0

                                Label {
                                    text: "Offset"
                                    color: theme.muted
                                    font.family: "Menlo"
                                    font.bold: true
                                    Layout.preferredWidth: 96
                                }

                                Repeater {
                                    model: 16
                                    delegate: Label {
                                        required property int modelData
                                        text: ("0" + modelData.toString(16)).slice(-2).toUpperCase()
                                        color: theme.muted
                                        font.family: "Menlo"
                                        font.bold: true
                                        Layout.preferredWidth: 28
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                Label {
                                    text: "ASCII"
                                    color: theme.muted
                                    font.family: "Menlo"
                                    font.bold: true
                                    Layout.leftMargin: 16
                                }
                            }
                        }

                        ListView {
                            id: listView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: backend.rowCount
                            cacheBuffer: 1200
                            ScrollBar.vertical: ScrollBar { }

                            Connections {
                                target: backend
                                function onSelectionChanged() {
                                    if (backend.selectedOffset >= 0) {
                                        listView.positionViewAtIndex(Math.floor(backend.selectedOffset / 16), ListView.Center)
                                    }
                                }
                            }

                            delegate: Rectangle {
                                required property int index
                                property int revision: backend.revision
                                color: index % 2 === 0 ? "#383b4c" : "#404458"
                                radius: 8
                                height: 28
                                width: listView.width

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 0

                                    Label {
                                        text: backend.addressForRow(index)
                                        color: theme.muted
                                        font.family: "Menlo"
                                        font.bold: true
                                        Layout.preferredWidth: 96
                                    }

                                    Repeater {
                                        model: 16
                                        delegate: ByteCellEditor {
                                            required property int modelData
                                            row: index
                                            column: modelData
                                            offset: index * 16 + modelData
                                            mode: "hex"
                                            width: 28
                                        }
                                    }

                                    RowLayout {
                                        Layout.leftMargin: 16
                                        spacing: 2

                                        Repeater {
                                            model: 16
                                            delegate: ByteCellEditor {
                                                required property int modelData
                                                row: index
                                                column: modelData
                                                offset: index * 16 + modelData
                                                mode: "text"
                                                width: 14
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                Frame {
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 12
                        color: theme.panelAlt
                        border.color: theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        RowLayout {
                            spacing: 12

                            Label {
                                text: backend.selectedOffset >= 0
                                    ? backend.addressForRow(Math.floor(backend.selectedOffset / 16)) + " @ " + backend.selectedOffset
                                    : "No selection"
                                color: theme.text
                                font.family: "Menlo"
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            Label { text: "Length"; color: theme.muted }
                            SpinBox {
                                from: 1
                                to: Math.max(backend.dataCount, 1)
                                value: backend.selectionLength
                                onValueModified: backend.selectionLength = value
                            }

                            LabeledTextField {
                                label: "Move"
                                text: backend.jumpQuery
                                placeholderText: "0x0"
                                Layout.preferredWidth: 160
                                onFieldEdited: backend.jumpQuery = value
                            }

                            Button { text: "Go"; onClicked: backend.moveSelection() }
                        }

                        Label {
                            text: "Click any hex or text byte, then type or paste. Copy uses the focused pane."
                            color: theme.muted
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            spacing: 12

                            LabeledTextField {
                                id: hexEdit
                                label: "Hex"
                                text: backend.selectedHexText
                                placeholderText: "4F 70 65 6E"
                                Layout.fillWidth: true
                            }

                            Button { text: "Apply Hex"; onClicked: backend.applyHexEdit(hexEdit.text) }
                        }

                        RowLayout {
                            spacing: 12

                            LabeledTextField {
                                id: textEdit
                                label: "Text"
                                text: backend.selectedTextText
                                placeholderText: "Editable UTF-8 text"
                                Layout.fillWidth: true
                            }

                            Button { text: "Apply Text"; onClicked: backend.applyTextEdit(textEdit.text) }
                        }

                        Connections {
                            target: backend
                            function onSelectionChanged() {
                                hexEdit.text = backend.selectedHexText
                                textEdit.text = backend.selectedTextText
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 10

                            Button {
                                text: "Export Hex…"
                                onClicked: {
                                    window.exportMode = 1
                                    exportDialog.open()
                                }
                            }
                            Button {
                                text: "Export Text…"
                                onClicked: {
                                    window.exportMode = 2
                                    exportDialog.open()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 24
        visible: !backend.hasFile

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 28
            color: isDragActive ? "#3a3d50" : "#303241"
            border.width: 3
            border.color: "#d8def4"

            property bool isDragActive: window.dragActive

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 18

                Label {
                    text: "Drop a file or application here."
                    color: theme.text
                    font.pixelSize: 30
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    text: "Choose a file below if you'd rather browse manually."
                    color: theme.muted
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Button {
            text: "Choose File"
            Layout.alignment: Qt.AlignHCenter
            onClicked: openDialog.open()
        }

        Item { Layout.fillHeight: true }
    }

    TabBar {
        id: tabs
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: header.height + 10
        visible: backend.hasFile

        TabButton { text: "Info & Hashes" }
        TabButton { text: "Hex Editor" }
    }

    component ByteCellEditor: TextField {
        id: editor
        required property int row
        required property int column
        required property int offset
        required property string mode

        readonly property bool exists: backend.cellExists(row, column)
        readonly property int replacementLength: backend.selectedOffset === offset ? Math.max(backend.selectionLength, 1) : 1

        implicitHeight: 24
        enabled: exists
        visible: true
        readOnly: !exists
        selectByMouse: true
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        color: backend.isOffsetSelected(offset) ? theme.accentText : theme.text
        selectedTextColor: theme.accentText
        selectionColor: theme.accent
        font.family: "Menlo"
        font.pixelSize: 12
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        focus: exists && window.focusedOffset === offset && window.focusedMode === mode

        function displayValue() {
            if (!exists) {
                return mode === "hex" ? "  " : " "
            }

            return mode === "hex"
                ? backend.hexValueAt(row, column)
                : backend.asciiValueAt(row, column)
        }

        function syncFromModel() {
            if (!activeFocus) {
                text = displayValue()
            }
        }

        function advanceFocus(bytesWritten) {
            if (backend.dataCount <= 0) {
                window.focusedOffset = -1
                return
            }

            const nextOffset = Math.min(offset + Math.max(bytesWritten, 1), backend.dataCount - 1)
            window.focusedOffset = nextOffset
            window.focusedMode = mode
            backend.selectOffset(nextOffset)
        }

        function handleEdit(value) {
            if (!exists) {
                return
            }

            if (mode === "hex") {
                const filtered = value.toUpperCase().replace(/[^0-9A-F]/g, "")
                if (filtered !== value) {
                    text = filtered
                    return
                }

                if (filtered.length === 0 || filtered.length % 2 !== 0) {
                    return
                }

                const written = backend.replaceHexInput(filtered, offset, replacementLength)
                if (written > 0) {
                    syncFromModel()
                    advanceFocus(written)
                }
                return
            }

            if (value.length === 0) {
                return
            }

            const written = backend.replaceTextInput(value, offset, replacementLength)
            if (written > 0) {
                syncFromModel()
                advanceFocus(written)
            }
        }

        Component.onCompleted: syncFromModel()
        onTextEdited: handleEdit(text)
        onActiveFocusChanged: {
            if (activeFocus) {
                window.focusedOffset = offset
                window.focusedMode = mode
                backend.selectOffset(offset)
                selectAll()
            } else {
                syncFromModel()
            }
        }

        Connections {
            target: backend
            function onRevisionChanged() {
                if (!activeFocus) {
                    syncFromModel()
                }
            }
        }

        Shortcut {
            enabled: editor.activeFocus
            sequence: StandardKey.Copy
            onActivated: backend.copySelection(editor.mode)
        }

        background: Rectangle {
            radius: mode === "hex" ? 6 : 4
            color: backend.isOffsetSelected(offset) ? theme.accent : "transparent"
            border.color: editor.activeFocus ? theme.text : "transparent"
            border.width: editor.activeFocus ? 1 : 0
        }
    }

    component DetailRow: RowLayout {
        property string label
        property string value
        spacing: 10

        Label {
            text: parent.label
            color: theme.muted
            font.bold: true
            Layout.preferredWidth: 96
        }

        TextArea {
            text: parent.value
            color: theme.text
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            background: null
            Layout.fillWidth: true
        }
    }

    component HashRow: RowLayout {
        property string label
        property string value
        spacing: 10

        Label {
            text: parent.label
            color: theme.muted
            font.bold: true
            Layout.preferredWidth: 96
        }

        TextArea {
            text: parent.value
            color: theme.text
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            background: null
            Layout.fillWidth: true
        }

        Button {
            text: "Copy"
            onClicked: backend.copyText(parent.value)
        }
    }

    component LabeledTextField: RowLayout {
        property string label
        property alias text: input.text
        property alias placeholderText: input.placeholderText
        signal fieldEdited(string value)

        spacing: 8

        Label {
            text: parent.label
            color: theme.muted
            font.bold: true
            Layout.preferredWidth: 58
        }

        TextField {
            id: input
            Layout.fillWidth: true
            color: theme.text
            placeholderTextColor: theme.muted
            selectByMouse: true
            font.family: "Menlo"
            onTextEdited: parent.fieldEdited(text)
            background: Rectangle {
                radius: 10
                color: "#2e313f"
                border.color: theme.border
            }
        }
    }
}
