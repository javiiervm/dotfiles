import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import ".."

// An in-Launcher image picker. It never creates a native dialog or window,
// so the Launcher keeps keyboard focus throughout the selection workflow.
Item {
    id: picker

    property int maxImages: 4
    property var selectedImages: []
    property url currentFolder: "file://" + Quickshell.env("HOME")
    property string searchQuery: ""
    property bool showHiddenFiles: false
    property string warning: ""

    readonly property int maxImageBytes: 8 * 1024 * 1024
    readonly property string homePath: String(Quickshell.env("HOME"))

    signal accepted(var images)
    signal canceled()

    visible: false
    focus: visible

    function pathFromUrl(fileUrl) {
        const value = String(fileUrl)
        if (!value.startsWith("file:///"))
            return ""
        try {
            return decodeURIComponent(value.substring("file://".length))
        } catch (error) {
            return ""
        }
    }

    function displayFolder() {
        return pathFromUrl(currentFolder) || homePath
    }

    function fileUrlForPath(path) {
        let value = String(path).trim()
        if (value === "~")
            value = homePath
        else if (value.startsWith("~/"))
            value = homePath + value.substring(1)
        if (!value.startsWith("/"))
            return ""
        return "file://" + encodeURI(value).replace(/#/g, "%23").replace(/\?/g, "%3F")
    }

    function browse(folderUrl) {
        if (!String(folderUrl).startsWith("file:///"))
            return
        currentFolder = folderUrl
        searchQuery = ""
        searchInput.text = ""
        locationInput.text = displayFolder()
        warning = ""
        folderList.positionViewAtBeginning()
    }

    function browsePath(path) {
        const url = fileUrlForPath(path)
        if (!url) {
            warning = "Enter an absolute folder path."
            locationInput.text = displayFolder()
            return
        }
        browse(url)
    }

    function openWith(images) {
        selectedImages = Array.isArray(images) ? images.slice() : []
        currentFolder = fileUrlForPath(homePath)
        searchQuery = ""
        searchInput.text = ""
        locationInput.text = displayFolder()
        warning = ""
        visible = true
        Qt.callLater(function() { searchInput.forceActiveFocus() })
    }

    function cancel() {
        if (!visible)
            return
        visible = false
        canceled()
    }

    function confirm() {
        const selection = selectedImages.slice()
        visible = false
        accepted(selection)
    }

    function isSelected(url) {
        const path = pathFromUrl(url)
        for (let i = 0; i < selectedImages.length; ++i) {
            if (selectedImages[i].path === path)
                return true
        }
        return false
    }

    function toggleFile(fileUrl, fileSize) {
        const url = String(fileUrl)
        const path = pathFromUrl(url)
        if (!path || !/\.(png|jpe?g|webp)$/i.test(path)) {
            warning = "Only PNG, JPEG and WebP images are supported."
            return
        }

        const updated = selectedImages.slice()
        let found = -1
        for (let i = 0; i < updated.length; ++i) {
            if (updated[i].path === path) {
                found = i
                break
            }
        }
        if (found >= 0) {
            updated.splice(found, 1)
        } else {
            if (Number(fileSize) > maxImageBytes) {
                warning = "This image is larger than 8 MiB."
                return
            }
            if (updated.length >= maxImages) {
                warning = "You can attach up to " + maxImages + " images."
                return
            }
            updated.push({ path: path, url: url })
        }
        selectedImages = updated
        warning = ""
    }

    Keys.onEscapePressed: function(event) {
        picker.cancel()
        event.accepted = true
    }

    // This is inside XavionEmbedded, so no native top-level window is created.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg0, 0.77)
        MouseArea {
            anchors.fill: parent
            onClicked: {} // The background is intentionally modal.
        }
    }

    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 28, 650)
        height: Math.min(parent.height - 30, 594)
        radius: 21
        clip: true
        color: Qt.alpha(Theme.bg0, 0.98)
        border.width: 1
        border.color: Qt.alpha(Theme.white, 0.23)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Header: same neutral glass language as the Launcher.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 10

                Text {
                    text: "Attach images"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 17
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    text: picker.selectedImages.length + " / " + picker.maxImages
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: closeHover.containsMouse
                           ? Qt.alpha(Theme.white, 0.16)
                           : Qt.alpha(Theme.white, 0.07)
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.white
                        font.pixelSize: 20
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.cancel()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 11

                // Quick locations stay inside the existing Xavion surface.
                Rectangle {
                    Layout.preferredWidth: Math.min(126, dialogCard.width * 0.23)
                    Layout.fillHeight: true
                    radius: 13
                    color: Qt.alpha(Theme.white, 0.055)
                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.08)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 5

                        Repeater {
                            model: [
                                { name: "Home", path: picker.homePath, symbol: "⌂" },
                                { name: "Pictures", path: picker.homePath + "/Pictures", symbol: "▧" },
                                { name: "Downloads", path: picker.homePath + "/Downloads", symbol: "↓" },
                                { name: "Documents", path: picker.homePath + "/Documents", symbol: "▤" },
                                { name: "Desktop", path: picker.homePath + "/Desktop", symbol: "▦" },
                                { name: "Other", path: "/", symbol: "/" }
                            ]
                            Rectangle {
                                id: shortcut
                                required property var modelData
                                readonly property bool active: picker.displayFolder() === String(modelData.path)
                                width: parent.width
                                height: 38
                                radius: 9
                                color: shortcutMouse.containsMouse || active
                                       ? Qt.alpha(Theme.white, 0.13)
                                       : "transparent"
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text {
                                        text: shortcut.modelData.symbol
                                        color: Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 16
                                        width: 16
                                    }
                                    Text {
                                        text: shortcut.modelData.name
                                        color: Qt.alpha(Theme.white, 0.94)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 11
                                    }
                                }
                                MouseArea {
                                    id: shortcutMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: picker.browsePath(shortcut.modelData.path)
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 9

                    // You can navigate with the parent button or type a path.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 35
                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 35
                            Layout.preferredHeight: 35
                            radius: 10
                            color: upMouse.containsMouse
                                   ? Qt.alpha(Theme.white, 0.16)
                                   : Qt.alpha(Theme.white, 0.075)
                            Text {
                                anchors.centerIn: parent
                                text: "↑"
                                color: Theme.white
                                font.pixelSize: 19
                            }
                            MouseArea {
                                id: upMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.browse(folderModel.parentFolder)
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 35
                            radius: 10
                            color: Qt.alpha(Theme.white, 0.075)
                            border.width: 1
                            border.color: locationInput.activeFocus
                                          ? Qt.alpha(Theme.white, 0.23)
                                          : Qt.alpha(Theme.white, 0.11)
                            TextInput {
                                id: locationInput
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 9
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                selectByMouse: true
                                clip: true
                                onAccepted: picker.browsePath(text)
                                Keys.onEscapePressed: function(event) {
                                    picker.cancel()
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 10
                        color: Qt.alpha(Theme.white, 0.075)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                            text: "Search in this folder..."
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            color: Theme.grey1
                        }
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 9
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: picker.searchQuery = text
                            Keys.onEscapePressed: function(event) {
                                picker.cancel()
                                event.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        clip: true
                        color: Qt.alpha(Theme.white, 0.045)
                        border.width: 1
                        border.color: Qt.alpha(Theme.white, 0.085)

                        FolderListModel {
                            id: folderModel
                            folder: picker.currentFolder
                            showDirs: true
                            showFiles: true
                            showHidden: picker.showHiddenFiles
                            showDotAndDotDot: false
                            showDirsFirst: true
                            sortField: FolderListModel.Name
                            showOnlyReadable: true
                            nameFilters: [
                                "*.png", "*.jpg", "*.jpeg", "*.webp",
                                "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"
                            ]
                        }

                        ListView {
                            id: folderList
                            anchors.fill: parent
                            anchors.margins: 5
                            model: folderModel
                            spacing: 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: fileEntry
                                required property string fileName
                                required property url fileUrl
                                required property bool fileIsDir
                                required property var fileSize

                                readonly property bool matchesSearch:
                                    picker.searchQuery.length === 0
                                    || fileName.toLowerCase().indexOf(picker.searchQuery.toLowerCase()) !== -1
                                readonly property bool chosen: picker.isSelected(fileUrl)
                                readonly property bool tooLarge: !fileIsDir
                                    && Number(fileSize) > picker.maxImageBytes

                                width: folderList.width
                                height: matchesSearch ? 57 : 0
                                visible: matchesSearch
                                radius: 10
                                color: chosen
                                       ? Qt.alpha(picker.accentColor, 0.22)
                                       : fileHover.containsMouse
                                         ? Qt.alpha(Theme.white, 0.105)
                                         : "transparent"
                                border.width: chosen ? 1 : 0
                                border.color: chosen ? Qt.alpha(picker.accentColor, 0.63) : "transparent"

                                Rectangle {
                                    id: filePreview
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 42
                                    height: 42
                                    radius: 8
                                    clip: true
                                    color: Qt.alpha(Theme.white, 0.075)
                                    Image {
                                        anchors.fill: parent
                                        visible: !fileEntry.fileIsDir && !fileEntry.tooLarge
                                        source: visible ? fileEntry.fileUrl : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        cache: false
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: fileEntry.fileIsDir || fileEntry.tooLarge
                                        text: fileEntry.fileIsDir ? "" : ""
                                        color: Theme.white
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 20
                                    }
                                }
                                Column {
                                    anchors.left: filePreview.right
                                    anchors.leftMargin: 9
                                    anchors.right: mark.left
                                    anchors.rightMargin: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text {
                                        width: parent.width
                                        text: fileEntry.fileName
                                        color: fileEntry.tooLarge ? Theme.grey1 : Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                    Text {
                                        width: parent.width
                                        text: fileEntry.fileIsDir ? "Folder"
                                              : fileEntry.tooLarge ? "Over 8 MiB"
                                              : (Number(fileEntry.fileSize) / (1024 * 1024)).toFixed(1) + " MiB"
                                        color: Theme.grey1
                                        font.family: Theme.fontMain
                                        font.pixelSize: 10
                                    }
                                }
                                Rectangle {
                                    id: mark
                                    anchors.right: parent.right
                                    anchors.rightMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20
                                    height: 20
                                    radius: 10
                                    visible: !fileEntry.fileIsDir
                                    color: fileEntry.chosen ? picker.accentColor : "transparent"
                                    border.width: 1
                                    border.color: fileEntry.chosen ? picker.accentColor
                                                  : Qt.alpha(Theme.white, 0.35)
                                    Text {
                                        anchors.centerIn: parent
                                        visible: fileEntry.chosen
                                        text: "✓"
                                        font.pixelSize: 13
                                        color: Theme.white
                                    }
                                }
                                MouseArea {
                                    id: fileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (fileEntry.fileIsDir)
                                            picker.browse(fileEntry.fileUrl)
                                        else
                                            picker.toggleFile(fileEntry.fileUrl, fileEntry.fileSize)
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: folderModel.status === FolderListModel.Ready
                                     && folderModel.count === 0
                            text: "No images or folders found"
                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 25
                        spacing: 8
                        Rectangle {
                            Layout.preferredWidth: 17
                            Layout.preferredHeight: 17
                            radius: 5
                            color: picker.showHiddenFiles
                                   ? Qt.alpha(Theme.white, 0.23)
                                   : Qt.alpha(Theme.white, 0.06)
                            border.width: 1
                            border.color: Qt.alpha(Theme.white, 0.25)
                            Text {
                                anchors.centerIn: parent
                                visible: picker.showHiddenFiles
                                text: "✓"
                                font.pixelSize: 12
                                color: Theme.white
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.showHiddenFiles = !picker.showHiddenFiles
                            }
                        }
                        Text {
                            text: "Show hidden files"
                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.showHiddenFiles = !picker.showHiddenFiles
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "PNG · JPEG · WebP"
                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: picker.warning.length > 0 ? 18 : 0
                visible: picker.warning.length > 0
                text: picker.warning
                color: Theme.red
                font.family: Theme.fontMain
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 39
                spacing: 9
                Text {
                    Layout.fillWidth: true
                    text: picker.selectedImages.length + " image" +
                          (picker.selectedImages.length === 1 ? "" : "s") + " selected"
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }
                Rectangle {
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 37
                    radius: 11
                    color: cancelHover.containsMouse
                           ? Qt.alpha(Theme.white, 0.17)
                           : Qt.alpha(Theme.white, 0.09)
                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.14)
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: cancelHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.cancel()
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 109
                    Layout.preferredHeight: 37
                    radius: 11
                    color: confirmHover.containsMouse
                           ? Qt.alpha(Theme.white, 0.25)
                           : Qt.alpha(Theme.white, 0.17)
                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.22)
                    Text {
                        anchors.centerIn: parent
                        text: "Attach (" + picker.selectedImages.length + ")"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: confirmHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.confirm()
                    }
                }
            }
        }
    }

    // The caller sets this to the same accent that is used in chat messages.
    property color accentColor: Theme.blue
}
