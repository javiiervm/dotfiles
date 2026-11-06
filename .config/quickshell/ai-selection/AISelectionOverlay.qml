
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Two layer-shell surfaces per output: a frozen screenshot for selection,
// and a transparent menu-only surface above it. The separate menu surface
// lets Hyprland apply compositor blur exactly as in Launcher.qml, rather
// than simulated QML texture blur within the screenshot surface.
Scope {
    id: selectionScope
    required property var modelData
    required property var controller

    PanelWindow {
        id: panel

        readonly property var modelData: selectionScope.modelData
        readonly property var controller: selectionScope.controller
        screen: selectionScope.modelData

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ai-selection"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        visible: controller.active

        property int captureSession: 0
        property string framePath: ""
        property bool selecting: false
        property bool hasSelection: false
        property bool saving: false
        property string xavionCapturePath: ""
        property int xavionCaptureSession: -1
        property bool localSelectionCompleted: false
        property real introProgress: 0

        // Local OCR is activated on demand by the text-selection toggle.
        // Recognized words are selected directly on the frozen screenshot;
        // no duplicate text view or large OCR panel is displayed.
        property bool textMode: false
        property bool ocrBusy: false
        property bool ocrReady: false
        property string ocrError: ""
        property var ocrWords: []
        property real ocrScaleX: 1
        property real ocrScaleY: 1
        property int ocrAnchor: -1
        property int ocrEnd: -1
        property bool ocrDragging: false
        // Last text cursor position in screen-local coordinates. The contextual
        // copy button appears next to the pointer after a word selection.
        property real ocrPointerX: 0
        property real ocrPointerY: 0
        property int ocrRequestId: 0
        property int activeOcrRequest: -1
        property string copyStatus: ""
        property string ocrRawOutput: ""
        property string ocrStderrOutput: ""
        property bool ocrStdoutFinished: false
        property bool ocrExited: false
        property int ocrExitCode: -1

        // This is a separate Quickshell configuration. Importing the parent
        // shell's QML components is not supported by its module scanner.
        // Read the shared theme source as data instead, so the menu follows
        // changes made to the real dotfiles without duplicating GlassSurface.
        FileView {
            id: glassSettings
            path: Quickshell.env("HOME") + "/.config/quickshell/Glass.qml"
            watchChanges: true
            onFileChanged: reload()
        }

        FileView {
            id: themeSettings
            path: Quickshell.env("HOME") + "/.config/quickshell/Theme.qml"
            watchChanges: true
            onFileChanged: reload()
        }

        function settingString(source, key, fallback) {
            const match = source.match(new RegExp("\\b" + key + "\\s*:\\s*['\"]([^'\"]+)['\"]"))
            return match ? match[1] : fallback
        }

        function settingNumber(source, key, fallback) {
            const match = source.match(new RegExp("\\b" + key + "\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)"))
            return match ? Number(match[1]) : fallback
        }

        readonly property color menuTint: settingString(glassSettings.text(), "tint", "#101013")
        readonly property real menuOpacity: settingNumber(glassSettings.text(), "opacity", 0.38)
        readonly property real menuBorderWidth: settingNumber(glassSettings.text(), "borderWidth", 1.0)
        readonly property real menuBorderOpacity: settingNumber(glassSettings.text(), "borderOpacity", 0.20)
        readonly property real menuHighlightOpacity: settingNumber(glassSettings.text(), "highlightOpacity", 0.10)
        readonly property color menuForeground: settingString(themeSettings.text(), "fg", "#abb2bf")
        readonly property color menuWhite: settingString(themeSettings.text(), "white", "#ffffff")
        readonly property string menuFont: settingString(themeSettings.text(), "fontMain", "Adwaita Sans")

        // Launcher.qml and GlassSurface.qml use these exact theme roles.
        // Keep action surfaces driven by the shared material, not by ad hoc
        // extra opacity on the OCR buttons.
        function settingBoolean(source, key, fallback) {
            const match = source.match(new RegExp("\\b" + key + "\\s*:\\s*(true|false)\\b"))
            return match ? match[1] === "true" : fallback
        }

        readonly property bool menuBlurEnabled: settingBoolean(glassSettings.text(), "blurEnabled", true)
        readonly property color menuAccent: settingString(themeSettings.text(), "blue", "#61afef")
        readonly property real menuIdleButtonOpacity: 0.08
        readonly property real menuHoverButtonOpacity: 0.16
        readonly property real menuActiveButtonOpacity: 0.20
        readonly property real menuButtonBorderOpacity: 0.12

        // Read the active pywal palette generated by the wallpaper scripts.
        // This is the very same ~/.cache/wal/colors.json used by
        // ~/.config/hypr/scripts/apply_wal_border.sh.
        // Changes are watched by FileView: no polling or new background service.
        FileView {
            id: walPaletteFile
            path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
        }

        readonly property var wallpaperColors: {
            try {
                const palette = JSON.parse(walPaletteFile.text())
                return (palette && palette.colors && typeof palette.colors === "object")
                    ? palette.colors : ({})
            } catch (error) {
                // No cache yet, or wal is currently replacing the file.
                return ({})
            }
        }

        function walColor(key, fallback) {
            const value = wallpaperColors[key]
            return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)
                   ? value : fallback
        }

        // These five roles all follow the current wallpaper's pywal swatches.
        // Keeping the original values as fallbacks prevents a broken/unavailable
        // cache from hiding the selection or breaking the QML configuration.
        readonly property string overlayBaseColor: walColor("color4", "#3264c7")
        readonly property string wavePrimaryColor: walColor("color5", "#a966f6")
        readonly property string waveSecondaryColor: walColor("color6", "#4ad2f5")
        readonly property string selectionPrimaryColor: walColor("color1", "#8de4ff")
        readonly property string selectionSecondaryColor: walColor("color2", "#77b9fd")

        // CanvasGradient requires CSS colours, so convert the pywal hex values.
        function withAlpha(hex, alpha) {
            const value = String(hex).replace("#", "")
            if (!/^[0-9a-fA-F]{6}$/.test(value))
                return "rgba(50, 100, 199, " + alpha + ")"
            const r = parseInt(value.substring(0, 2), 16)
            const g = parseInt(value.substring(2, 4), 16)
            const b = parseInt(value.substring(4, 6), 16)
            return "rgba(" + r + ", " + g + ", " + b + ", " + alpha + ")"
        }

        // A real entrance transition: fade the bluish wash in over the frozen
        // screen before enabling dragging. The colour waves keep moving after it.
        NumberAnimation on introProgress {
            from: 0
            to: 1
            duration: 320
            running: panel.visible
            easing.type: Easing.OutCubic
        }

        property real pressX: 0
        property real pressY: 0
        property real endX: 0
        property real endY: 0

        readonly property real leftEdge: Math.min(pressX, endX)
        readonly property real topEdge: Math.min(pressY, endY)
        readonly property real selectionWidth: Math.abs(endX - pressX)
        readonly property real selectionHeight: Math.abs(endY - pressY)

        function clearSelection() {
            selecting = false
            hasSelection = false
            pressX = 0
            pressY = 0
            endX = 0
            endY = 0
        }

        function resetTextMode() {
            ++ocrRequestId
            activeOcrRequest = -1
            ocrRawOutput = ""
            ocrStderrOutput = ""
            ocrStdoutFinished = false
            ocrExited = false
            if (ocrProcess.running)
                ocrProcess.running = false
            textMode = false
            ocrBusy = false
            ocrReady = false
            ocrError = ""
            ocrWords = []
            ocrAnchor = -1
            ocrEnd = -1
            ocrDragging = false
            copyStatus = ""
            copyStatusTimer.stop()
        }

        function toggleTextMode() {
            if (!hasSelection || saving)
                return

            textMode = !textMode
            ocrAnchor = -1
            ocrEnd = -1
            ocrDragging = false
            copyStatus = ""
            copyStatusTimer.stop()
            if (!textMode)
                return
            if (!ocrReady && !ocrBusy)
                startOcr()
        }

        function startOcr() {
            if (!hasSelection || framePath === "" || ocrBusy || ocrProcess.running)
                return

            const sx = frozenImage.sourceSize.width / panel.width
            const sy = frozenImage.sourceSize.height / panel.height
            if (!(sx > 0 && sy > 0))
                return

            const x = Math.max(0, Math.round(leftEdge * sx))
            const y = Math.max(0, Math.round(topEdge * sy))
            const w = Math.min(frozenImage.sourceSize.width - x,
                               Math.max(1, Math.round(selectionWidth * sx)))
            const h = Math.min(frozenImage.sourceSize.height - y,
                               Math.max(1, Math.round(selectionHeight * sy)))
            if (w < 4 || h < 4)
                return

            // The image is doubled for better recognition of small interface text;
            // TSV bounding boxes are converted back to logical QML coordinates.
            ocrScaleX = selectionWidth / (w * 2)
            ocrScaleY = selectionHeight / (h * 2)
            ocrBusy = true
            ocrReady = false
            ocrError = ""
            ocrWords = []
            ocrAnchor = -1
            ocrEnd = -1
            activeOcrRequest = ++ocrRequestId
            ocrRawOutput = ""
            ocrStderrOutput = ""
            ocrStdoutFinished = false
            ocrExited = false
            ocrExitCode = -1

            // Do not interpolate paths into shell code: positional arguments only.
            // OCR runs locally and never uploads the captured content.
            ocrProcess.exec([
                "bash", "-c",
                "set -euo pipefail\n" +
                "image=$1; x=$2; y=$3; w=$4; h=$5\n" +
                "magick \"$image\" -crop \"${w}x${h}+${x}+${y}\" +repage " +
                "-resize 200% png:- | " +
                "tesseract stdin stdout -l eng+spa --psm 3 tsv",
                "ai-selection-ocr", framePath, String(x), String(y), String(w), String(h)
            ])
        }

        function finishOcr(exitCode, output, requestId) {
            if (requestId !== activeOcrRequest || requestId < 0)
                return
            ocrBusy = false
            activeOcrRequest = -1
            if (exitCode !== 0) {
                ocrError = "OCR failed. Install Tesseract and the English/Spanish language data."
                console.warn("AI Selection: local OCR failed with exit code", exitCode)
                return
            }

            const rows = String(output).split(/\r?\n/)
            const found = []
            for (let i = 1; i < rows.length; ++i) {
                const cols = rows[i].split("\t")
                if (cols.length < 12 || cols[0] !== "5")
                    continue
                const confidence = Number(cols[10])
                const left = Number(cols[6])
                const top = Number(cols[7])
                const width = Number(cols[8])
                const height = Number(cols[9])
                const word = cols.slice(11).join("\t").trim()
                if (!word || !isFinite(confidence) || confidence < 0
                    || !isFinite(left) || !isFinite(top)
                    || !isFinite(width) || !isFinite(height)
                    || width <= 0 || height <= 0)
                    continue
                found.push({
                    text: word,
                    line: cols[1] + ":" + cols[2] + ":" + cols[3] + ":" + cols[4],
                    paragraph: cols[1] + ":" + cols[2] + ":" + cols[3],
                    left: left, top: top, width: width, height: height
                })
            }

            ocrWords = found
            ocrReady = true
            ocrError = found.length ? "" : "No text detected in this selection."
        }

        function wordAt(x, y, nearest) {
            let best = -1
            let bestDistance = Number.POSITIVE_INFINITY
            for (let i = 0; i < ocrWords.length; ++i) {
                const word = ocrWords[i]
                const wx = word.left * ocrScaleX
                const wy = word.top * ocrScaleY
                const ww = word.width * ocrScaleX
                const wh = word.height * ocrScaleY
                const dx = Math.max(wx - x, 0, x - wx - ww)
                const dy = Math.max(wy - y, 0, y - wy - wh)
                const distance = dx * dx + dy * dy * 4
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = i
                }
            }
            // Initial click must land on or close to a recognized word.
            return (nearest || bestDistance < 100) ? best : -1
        }

        function startWordSelection(x, y) {
            const word = wordAt(x, y, false)
            ocrAnchor = word
            ocrEnd = word
            ocrDragging = word >= 0
        }

        function updateWordSelection(x, y) {
            if (!ocrDragging || ocrAnchor < 0)
                return
            const word = wordAt(x, y, true)
            if (word >= 0)
                ocrEnd = word
        }

        function inWordSelection(index) {
            return ocrAnchor >= 0 && ocrEnd >= 0
                   && index >= Math.min(ocrAnchor, ocrEnd)
                   && index <= Math.max(ocrAnchor, ocrEnd)
        }

        function selectedWordsText() {
            if (ocrAnchor < 0 || ocrEnd < 0 || !ocrWords.length)
                return ""
            const first = Math.min(ocrAnchor, ocrEnd)
            const last = Math.max(ocrAnchor, ocrEnd)
            let result = ""
            for (let i = first; i <= last; ++i) {
                const word = ocrWords[i]
                if (i > first) {
                    const previous = ocrWords[i - 1]
                    result += word.paragraph !== previous.paragraph ? "\n\n"
                              : (word.line !== previous.line ? "\n" : " ")
                }
                result += word.text
            }
            return result
        }

        function copyRecognizedText() {
            if (!textMode || !ocrReady || ocrAnchor < 0 || ocrEnd < 0
                || copyProcess.running)
                return
            const text = selectedWordsText()
            if (!text)
                return
            copyStatus = ""
            // User text is carried in argv, never evaluated as shell syntax.
            copyProcess.exec([
                "bash", "-c",
                "printf '%s' \"$1\" | wl-copy --type 'text/plain;charset=utf-8'",
                "ai-selection-copy", text
            ])
        }

        function askXavion() {
            if (!hasSelection || saving || framePath === "")
                return

            const sx = frozenImage.sourceSize.width / panel.width
            const sy = frozenImage.sourceSize.height / panel.height
            const x = Math.max(0, Math.round(leftEdge * sx))
            const y = Math.max(0, Math.round(topEdge * sy))
            const w = Math.min(frozenImage.sourceSize.width - x,
                               Math.max(1, Math.round(selectionWidth * sx)))
            const h = Math.min(frozenImage.sourceSize.height - y,
                               Math.max(1, Math.round(selectionHeight * sy)))
            if (w < 2 || h < 2)
                return

            const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
            const suffix = Date.now() + "-" + Math.floor(Math.random() * 1000000000)
            xavionCapturePath = runtime + "/xavion-ai-selection-" + suffix + ".png"
            xavionCaptureSession = controller.session
            saving = true
            xavionCropProcess.exec([
                "bash", "-c",
                "set -euo pipefail\n" +
                "umask 077\n" +
                "source=$1; x=$2; y=$3; w=$4; h=$5; out=$6\n" +
                "if command -v magick >/dev/null 2>&1; then\n" +
                "  magick \"$source\" -crop \"${w}x${h}+${x}+${y}\" +repage \"$out\"\n" +
                "else\n" +
                "  convert \"$source\" -crop \"${w}x${h}+${x}+${y}\" +repage \"$out\"\n" +
                "fi\n" +
                "test -s \"$out\"\n" +
                "size=$(stat -c %s \"$out\")\n" +
                "if (( size > 8 * 1024 * 1024 )); then\n" +
                "  if command -v magick >/dev/null 2>&1; then\n" +
                "    magick \"$out\" -resize '1920x1920>' -strip \"$out\"\n" +
                "  else\n" +
                "    convert \"$out\" -resize '1920x1920>' -strip \"$out\"\n" +
                "  fi\n" +
                "fi\n" +
                "test $(stat -c %s \"$out\") -le $((8 * 1024 * 1024))\n",
                "ai-selection-xavion", framePath, String(x), String(y),
                String(w), String(h), xavionCapturePath
            ])
        }

        function saveSelection() {
            if (!hasSelection || saving || framePath === "")
                return

            // Wayland panels use logical coordinates; grim's PNG uses physical pixels.
            // Take both scale factors from the real source image, not screen.scale.
            const sx = frozenImage.sourceSize.width / panel.width
            const sy = frozenImage.sourceSize.height / panel.height
            const x = Math.max(0, Math.round(leftEdge * sx))
            const y = Math.max(0, Math.round(topEdge * sy))
            const w = Math.min(frozenImage.sourceSize.width - x,
                               Math.max(1, Math.round(selectionWidth * sx)))
            const h = Math.min(frozenImage.sourceSize.height - y,
                               Math.max(1, Math.round(selectionHeight * sy)))
            if (w < 2 || h < 2)
                return

            saving = true

            // Pass all parameters as positional arguments; never interpolate paths
            // or coordinates into shell commands.
            saveProcess.exec([
                "bash", "-c",
                "set -euo pipefail\n" +
                "source_file=$1; x=$2; y=$3; w=$4; h=$5\n" +
                "pictures=$(xdg-user-dir PICTURES 2>/dev/null || printf '%s/Pictures' \"$HOME\")\n" +
                "directory=\"$pictures/Screenshots\"\n" +
                "mkdir -p -- \"$directory\"\n" +
                "filename=\"Screenshot_$(date +%Y-%m-%d_%H-%M-%S_%N).png\"\n" +
                "out=\"$directory/$filename\"\n" +
                "if command -v magick >/dev/null 2>&1; then\n" +
                "  magick \"$source_file\" -crop \"${w}x${h}+${x}+${y}\" +repage \"$out\"\n" +
                "else\n" +
                "  convert \"$source_file\" -crop \"${w}x${h}+${x}+${y}\" +repage \"$out\"\n" +
                "fi\n" +
                "wl-copy --type image/png < \"$out\"\n" +
                "touch /tmp/qs_shutter\n",
                "ai-selection", framePath, String(x), String(y), String(w), String(h)
            ])
        }

        Connections {
            target: controller
            // Keep the overlay compatible with controllers predating v0.3.
            ignoreUnknownSignals: true

            function onSnapshotRequested(requestSession) {
                panel.resetTextMode()
                panel.clearSelection()
                panel.introProgress = 0
                panel.localSelectionCompleted = false
                panel.saving = false
                panel.captureSession = requestSession
                frozenImage.source = ""

                const tempDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
                const safeName = panel.modelData.name.replace(/[^a-zA-Z0-9_-]/g, "_")
                panel.framePath = tempDir + "/ai-selection-" + safeName + "-" + requestSession + ".png"

                // The overlay is not visible until ALL monitors have been captured.
                // This prevents the AI overlay from leaking into the original PNG.
                // Temporary frozen frames live in XDG_RUNTIME_DIR (RAM-backed on
                // typical Linux setups). Level 0 avoids PNG compression work
                // before the UI can open; the final saved crop is still a
                // regular compressed PNG produced by ImageMagick.
                snapshotProcess.exec(["grim", "-l", "0", "-o", panel.modelData.name, panel.framePath])
            }

            // A selection on either monitor clears the previous selection.
            function onSelectionsCleared() {
                panel.resetTextMode()
                panel.clearSelection()
                panel.localSelectionCompleted = false
            }

            function onDismissed() {
                panel.resetTextMode()
                panel.clearSelection()
                panel.localSelectionCompleted = false
                panel.saving = false
                frozenImage.source = ""
                if (panel.framePath !== "")
                    cleanupProcess.exec(["rm", "-f", "--", panel.framePath])
                panel.framePath = ""
            }
        }

        Process {
            id: snapshotProcess
            onExited: function(exitCode, exitStatus) {
                // Ignore a screenshot that completed after the user cancelled.
                if (panel.captureSession !== panel.controller.session || !panel.controller.opening)
                    return
                if (exitCode !== 0) {
                    console.error("AI Selection: grim failed for", panel.modelData.name, exitCode)
                    panel.controller.abortSelection()
                    return
                }
                frozenImage.source = "file://" + panel.framePath
            }
        }

        Process {
            id: saveProcess
            onExited: function(exitCode, exitStatus) {
                if (exitCode !== 0) {
                    console.error("AI Selection: screenshot save/copy failed:", exitCode)
                    errorProcess.exec(["notify-send", "AI Selection",
                        "Could not save/copy screenshot. Check ImageMagick and wl-clipboard."])
                }
                panel.saving = false
                panel.controller.abortSelection()
            }
        }

        Process {
            id: xavionCropProcess
            onExited: function(exitCode, exitStatus) {
                // The user may have pressed Escape while cropping.
                if (panel.xavionCaptureSession !== panel.controller.session
                        || !panel.controller.active)
                    return
                if (exitCode !== 0) {
                    panel.saving = false
                    errorProcess.exec(["notify-send", "AI Selection",
                        "Could not prepare the selected image for Xavion."])
                    return
                }
                const capture = panel.xavionCapturePath
                // Close the exclusive-focus selection surface BEFORE opening
                // the Launcher; otherwise it would immediately lose focus.
                panel.controller.abortSelection()
                xavionIpcProcess.exec([
                    "qs", "ipc", "-p", Quickshell.env("HOME") + "/.config/quickshell",
                    "call", "xavioncapture", "open", capture
                ])
            }
        }

        Process {
            id: xavionIpcProcess
            onExited: function(exitCode, exitStatus) {
                if (exitCode !== 0)
                    errorProcess.exec(["notify-send", "AI Selection",
                        "Could not open Xavion. Is the main Quickshell instance running?"])
            }
        }

        Process { id: cleanupProcess }
        Process { id: errorProcess }

        Process {
            id: ocrProcess
            stdout: StdioCollector {
                onStreamFinished: {
                    panel.ocrRawOutput = this.text
                    panel.ocrStdoutFinished = true
                    if (panel.ocrExited)
                        panel.finishOcr(panel.ocrExitCode, panel.ocrRawOutput,
                                        panel.activeOcrRequest)
                }
            }
            stderr: StdioCollector {
                onStreamFinished: panel.ocrStderrOutput = this.text
            }
            onExited: function(exitCode, exitStatus) {
                if (exitCode !== 0)
                    console.warn("AI Selection Tesseract:", panel.ocrStderrOutput)
                panel.ocrExitCode = exitCode
                panel.ocrExited = true
                // Wait for both process completion AND the final stdout chunk.
                if (panel.ocrStdoutFinished)
                    panel.finishOcr(exitCode, panel.ocrRawOutput, panel.activeOcrRequest)
            }
        }

        Process {
            id: copyProcess
            onExited: function(exitCode, exitStatus) {
                panel.copyStatus = exitCode === 0 ? "Copied to clipboard" : "Copy failed"
                copyStatusTimer.restart()
            }
        }

        Timer {
            id: copyStatusTimer
            interval: 1800
            repeat: false
            onTriggered: panel.copyStatus = ""
        }

        Item {
            id: surface
            anchors.fill: parent
            focus: panel.visible
            Keys.onEscapePressed: {
                if (!panel.saving)
                    panel.controller.abortSelection()
            }

            // Keep Escape available even when a child MouseArea is active.
            Shortcut {
                sequence: "Escape"
                context: Qt.WindowShortcut
                enabled: panel.visible && !panel.saving
                onActivated: panel.controller.abortSelection()
            }

            Image {
                id: frozenImage
                anchors.fill: parent
                cache: false
                asynchronous: false
                fillMode: Image.Stretch
                visible: panel.visible

                onStatusChanged: {
                    if (status === Image.Ready && panel.captureSession === panel.controller.session)
                        panel.controller.snapshotReady(panel.captureSession)
                    else if (status === Image.Error)
                        panel.controller.abortSelection()
                }
            }

            // The wallpaper-coloured treatment is visible before dragging.
            // On the monitor being selected it disappears immediately, so no
            // colour leaks into the transparent selection region, even for a frame.
            // Other monitors keep the blue treatment until the selection is done.
            Item {
                id: blueTreatment
                anchors.fill: parent
                visible: !panel.selecting
                opacity: (panel.localSelectionCompleted
                          || panel.controller.selectionCompleted === true)
                         ? 0 : panel.introProgress

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    color: panel.overlayBaseColor
                    opacity: 0.32
                }

                // Large blurred colour waves. The Canvases are painted once and their
                // textures move on the GPU rather than repainting every frame.
                Item {
                    anchors.fill: parent
                    clip: true

                    Canvas {
                        id: violetWave
                        width: Math.max(panel.width * 0.70, 720)
                        height: Math.max(panel.height * 1.2, 720)
                        x: -width * 0.42
                        y: -height * 0.28
                        opacity: 0.58
                        readonly property string primarySwatch: panel.wavePrimaryColor
                        readonly property string secondarySwatch: panel.selectionPrimaryColor
                        onPrimarySwatchChanged: requestPaint()
                        onSecondarySwatchChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const r = Math.max(width, height) * 0.5
                            const gradient = ctx.createRadialGradient(width / 2, height / 2, 0,
                                                                       width / 2, height / 2, r)
                            gradient.addColorStop(0, panel.withAlpha(primarySwatch, 0.72))
                            gradient.addColorStop(0.55, panel.withAlpha(secondarySwatch, 0.32))
                            gradient.addColorStop(1, panel.withAlpha(primarySwatch, 0))
                            ctx.fillStyle = gradient
                            ctx.fillRect(0, 0, width, height)
                        }

                        SequentialAnimation on x {
                            running: panel.visible && blueTreatment.visible && blueTreatment.opacity > 0.01
                            loops: Animation.Infinite
                            NumberAnimation { to: panel.width * 0.30; duration: 3300; easing.type: Easing.InOutSine }
                            NumberAnimation { to: -violetWave.width * 0.42; duration: 3700; easing.type: Easing.InOutSine }
                        }
                    }

                    Canvas {
                        id: cyanWave
                        width: Math.max(panel.width * 0.75, 760)
                        height: Math.max(panel.height * 1.15, 700)
                        x: panel.width * 0.36
                        y: panel.height * 0.10
                        opacity: 0.60
                        readonly property string primarySwatch: panel.waveSecondaryColor
                        readonly property string secondarySwatch: panel.selectionSecondaryColor
                        onPrimarySwatchChanged: requestPaint()
                        onSecondarySwatchChanged: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const r = Math.max(width, height) * 0.5
                            const gradient = ctx.createRadialGradient(width / 2, height / 2, 0,
                                                                       width / 2, height / 2, r)
                            gradient.addColorStop(0, panel.withAlpha(primarySwatch, 0.68))
                            gradient.addColorStop(0.60, panel.withAlpha(secondarySwatch, 0.26))
                            gradient.addColorStop(1, panel.withAlpha(primarySwatch, 0))
                            ctx.fillStyle = gradient
                            ctx.fillRect(0, 0, width, height)
                        }

                        SequentialAnimation on y {
                            running: panel.visible && blueTreatment.visible && blueTreatment.opacity > 0.01
                            loops: Animation.Infinite
                            NumberAnimation { to: -cyanWave.height * 0.38; duration: 3800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: panel.height * 0.10; duration: 4200; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // Four wallpaper-coloured overlay strips leave a genuine transparent hole
            // over the selected pixels. The original frozen screenshot underneath
            // remains untouched, and there is no expensive full-screen mask/shader.
            // Adjust this value to change the colour strength outside the region.
            Item {
                id: dragTint
                anchors.fill: parent
                visible: panel.selecting
                readonly property real tintOpacity: 0.16

                // Above the selection.
                Rectangle {
                    x: 0
                    y: 0
                    width: dragTint.width
                    height: panel.topEdge
                    color: panel.overlayBaseColor
                    opacity: dragTint.tintOpacity
                }

                // To the left of the selection.
                Rectangle {
                    x: 0
                    y: panel.topEdge
                    width: panel.leftEdge
                    height: panel.selectionHeight
                    color: panel.overlayBaseColor
                    opacity: dragTint.tintOpacity
                }

                // To the right of the selection.
                Rectangle {
                    x: panel.leftEdge + panel.selectionWidth
                    y: panel.topEdge
                    width: Math.max(0, dragTint.width - x)
                    height: panel.selectionHeight
                    color: panel.overlayBaseColor
                    opacity: dragTint.tintOpacity
                }

                // Below the selection.
                Rectangle {
                    x: 0
                    y: panel.topEdge + panel.selectionHeight
                    width: dragTint.width
                    height: Math.max(0, dragTint.height - y)
                    color: panel.overlayBaseColor
                    opacity: dragTint.tintOpacity
                }
            }

            MouseArea {
                id: picker
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor
                // Input must not depend on animation state: it can remain at zero
                // after a reload or reopening and would lock selection completely.
                enabled: panel.visible && !panel.saving

                onPressed: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        panel.controller.abortSelection()
                        return
                    }
                    // Sync selections when the v0.3 controller is available.
                    // Older shell.qml versions lack this function; do not abort
                    // mouse input just because the UI controller is older.
                    if (typeof panel.controller.beginRegionSelection === "function")
                        panel.controller.beginRegionSelection()
                    else
                        panel.clearSelection()

                    panel.localSelectionCompleted = false
                    panel.selecting = true
                    panel.pressX = mouse.x
                    panel.pressY = mouse.y
                    panel.endX = mouse.x
                    panel.endY = mouse.y
                }

                onPositionChanged: function(mouse) {
                    if (panel.selecting) {
                        panel.endX = Math.max(0, Math.min(width, mouse.x))
                        panel.endY = Math.max(0, Math.min(height, mouse.y))
                    }
                }

                onReleased: function(mouse) {
                    if (!panel.selecting)
                        return
                    panel.endX = Math.max(0, Math.min(width, mouse.x))
                    panel.endY = Math.max(0, Math.min(height, mouse.y))
                    panel.selecting = false
                    panel.hasSelection = panel.selectionWidth >= 8 && panel.selectionHeight >= 8
                    if (panel.hasSelection) {
                        panel.localSelectionCompleted = true
                        if (typeof panel.controller.completeRegionSelection === "function")
                            panel.controller.completeRegionSelection()
                    } else if (typeof panel.controller.cancelRegionSelection === "function") {
                        // No valid region: return to the initial blue overlay.
                        panel.controller.cancelRegionSelection()
                    }
                }

                onCanceled: {
                    panel.selecting = false
                    if (typeof panel.controller.cancelRegionSelection === "function")
                        panel.controller.cancelRegionSelection()
                }
            }

            // The rectangle is presentation-only: the file used for the final
            // screenshot is the original, uncoloured PNG recorded by grim.
            Rectangle {
                x: panel.leftEdge
                y: panel.topEdge
                width: panel.selectionWidth
                height: panel.selectionHeight
                visible: panel.selecting || panel.hasSelection
                // Transparent interior: the user sees the original frozen pixels.
                color: "transparent"
                border.color: panel.selectionPrimaryColor
                border.width: 2
                radius: 9

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: panel.selectionSecondaryColor
                    opacity: 0.60
                }
            }

            // OCR text selection directly on the frozen screenshot. The original
            // pixels remain visible; word boxes only show when highlighted.
            Item {
                id: wordOverlay
                x: panel.leftEdge
                y: panel.topEdge
                width: panel.selectionWidth
                height: panel.selectionHeight
                visible: panel.textMode && panel.ocrReady && panel.hasSelection
                clip: true

                Repeater {
                    model: panel.ocrWords

                    Rectangle {
                        id: wordHighlight
                        readonly property var wordData: modelData
                        readonly property bool chosen: panel.inWordSelection(index)
                        x: wordData.left * panel.ocrScaleX - 1
                        y: wordData.top * panel.ocrScaleY - 1
                        width: wordData.width * panel.ocrScaleX + 2
                        height: wordData.height * panel.ocrScaleY + 2
                        radius: 3
                        color: chosen ? Qt.alpha(panel.selectionPrimaryColor, 0.36)
                                      : "transparent"
                        border.width: chosen ? 1 : 0
                        border.color: Qt.alpha(panel.selectionPrimaryColor, 0.85)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.IBeamCursor
                    onPressed: function(mouse) {
                        panel.ocrPointerX = wordOverlay.x + mouse.x
                        panel.ocrPointerY = wordOverlay.y + mouse.y
                        panel.startWordSelection(mouse.x, mouse.y)
                        panel.copyStatus = ""
                    }
                    onPositionChanged: function(mouse) {
                        if (panel.ocrDragging) {
                            panel.ocrPointerX = wordOverlay.x + mouse.x
                            panel.ocrPointerY = wordOverlay.y + mouse.y
                            panel.updateWordSelection(mouse.x, mouse.y)
                        }
                    }
                    onReleased: function(mouse) {
                        panel.ocrPointerX = wordOverlay.x + mouse.x
                        panel.ocrPointerY = wordOverlay.y + mouse.y
                        panel.updateWordSelection(mouse.x, mouse.y)
                        panel.ocrDragging = false
                    }
                    onCanceled: panel.ocrDragging = false
                }
            }

        } // surface
    } // frozen-screen panel

    // The Launcher uses BackgroundEffect.blurRegion on its own window.
    // That cannot blur child items on the SAME window as frozenImage:
    // compositor blur only affects surfaces already underneath. Keeping
    // the menus in a second layer-shell surface gives the compositor the
    // already-frozen image to blur, while preserving capture/selection.
    PanelWindow {
        id: menuWindow
        screen: selectionScope.modelData
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "ai-selection-menus"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        visible: panel.visible && panel.hasSelection && !panel.saving

        // Exactly as in Launcher.qml: region-controlled native compositor blur.
        // Use geometry without scaling to avoid stale regions during changes.
        BackgroundEffect.blurRegion: panel.menuBlurEnabled && menuWindow.visible
                                      ? menuBlurRegion : null

        // Transparent areas do not intercept pointer input: drag over words
        // still reaches the OCR layer beneath these menu buttons.
        mask: Region {
            Region {
                x: actions.x
                y: actions.y
                width: actions.visible ? actions.width : 0
                height: actions.visible ? actions.height : 0
                radius: actions.height / 2
            }
            Region {
                x: copyTextAction.x
                y: copyTextAction.y
                width: copyTextAction.visible ? copyTextAction.width : 0
                height: copyTextAction.visible ? copyTextAction.height : 0
                radius: copyTextAction.height / 2
            }
            Region {
                x: ocrStatus.x
                y: ocrStatus.y
                width: ocrStatus.visible ? ocrStatus.width : 0
                height: ocrStatus.visible ? ocrStatus.height : 0
                radius: ocrStatus.height / 2
            }
        }

        Region {
            id: menuBlurRegion
            Region {
                x: actions.x
                y: actions.y
                width: actions.visible ? actions.width : 0
                height: actions.visible ? actions.height : 0
                radius: actions.height / 2
            }
            Region {
                x: copyTextAction.x
                y: copyTextAction.y
                width: copyTextAction.visible ? copyTextAction.width : 0
                height: copyTextAction.visible ? copyTextAction.height : 0
                radius: copyTextAction.height / 2
            }
            Region {
                x: ocrStatus.x
                y: ocrStatus.y
                width: ocrStatus.visible ? ocrStatus.width : 0
                height: ocrStatus.visible ? ocrStatus.height : 0
                radius: ocrStatus.height / 2
            }
        }

        // Main selection toolbar. Glass rendering follows GlassSurface.qml;
        // native blur is applied by menuWindow behind this transparent surface.
        Item {
            id: actions
            visible: panel.hasSelection && !panel.saving
            // One labelled placeholder, OCR toggle, and working capture action.
            width: 218
            height: 44

            x: Math.max(12, Math.min(panel.width - width - 12,
                                    panel.leftEdge + (panel.selectionWidth - width) / 2))
            y: panel.topEdge + panel.selectionHeight + height + 12 < panel.height
               ? panel.topEdge + panel.selectionHeight + 12
               : Math.max(12, panel.topEdge - height - 12)



            // Identical surface treatment to GlassSurface.qml in the Launcher.
            Rectangle {
                anchors.fill: parent
                radius: actions.height / 2
                color: Qt.alpha(panel.menuTint, panel.menuOpacity)
                border.width: panel.menuBorderWidth
                border.color: Qt.alpha(panel.menuWhite, panel.menuBorderOpacity)

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: parent.radius / 2
                        rightMargin: parent.radius / 2
                    }
                    height: 1
                    color: Qt.alpha(panel.menuWhite, panel.menuHighlightOpacity)
                }
            }

            // Ask Xavion sends the cropped original image to a new draft.
            Row {
                anchors.centerIn: parent
                spacing: 5

                // Ask Xavion: create the crop and open the integrated chat.
                Rectangle {
                    id: askXavionButton
                    width: 126
                    height: 36
                    radius: 18
                    color: askXavionArea.containsMouse
                           ? Qt.alpha(panel.menuWhite, panel.menuHoverButtonOpacity)
                           : Qt.alpha(panel.menuWhite, panel.menuIdleButtonOpacity)
                    border.width: 1
                    border.color: Qt.alpha(panel.menuWhite, panel.menuButtonBorderOpacity)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Ask Xavion"
                        color: panel.menuWhite
                        font.family: panel.menuFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: askXavionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !panel.saving
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.askXavion()
                    }
                }

                // Toggle local OCR text recognition and selection.
                // The selection-corner + T icon is vector-drawn so it doesn't
                // rely on a particular Nerd Font glyph being installed.
                Rectangle {
                    id: textSelectionButton
                    width: 36
                    height: 36
                    radius: 18
                    // Match Launcher's neutral button states: selection colour
                    // belongs to the screenshot, while controls use Theme.
                    color: panel.textMode
                           ? Qt.alpha(panel.menuWhite, panel.menuActiveButtonOpacity)
                           : (textToggleArea.containsMouse
                              ? Qt.alpha(panel.menuWhite, panel.menuHoverButtonOpacity)
                              : Qt.alpha(panel.menuWhite, panel.menuIdleButtonOpacity))
                    border.width: 1
                    border.color: panel.textMode
                                  ? Qt.alpha(panel.menuAccent, 0.72)
                                  : Qt.alpha(panel.menuWhite, panel.menuButtonBorderOpacity)
                    opacity: 1

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Canvas {
                        id: textSelectionIcon
                        anchors.centerIn: parent
                        // The upper brackets carry more visual weight; a 1px
                        // optical offset centers the icon inside its pill.
                        anchors.verticalCenterOffset: 0
                        width: 24
                        height: 24
                        scale: 0.88
                        readonly property color iconColor: panel.menuWhite
                        onIconColorChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = String(iconColor)
                            ctx.lineWidth = 1.6
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            // Selection brackets.
                            ctx.moveTo(7, 4); ctx.lineTo(4, 4); ctx.lineTo(4, 8)
                            ctx.moveTo(17, 4); ctx.lineTo(20, 4); ctx.lineTo(20, 8)
                            ctx.moveTo(4, 16); ctx.lineTo(4, 20); ctx.lineTo(7, 20)
                            ctx.moveTo(20, 16); ctx.lineTo(20, 20); ctx.lineTo(17, 20)
                            // Text cursor / letter T.
                            ctx.moveTo(8, 9); ctx.lineTo(16, 9)
                            ctx.moveTo(12, 9); ctx.lineTo(12, 17)
                            ctx.stroke()
                        }
                    }

                    MouseArea {
                        id: textToggleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.toggleTextMode()
                    }
                }

                // Active: crop the original frozen image, save it and copy
                // the PNG to the clipboard (unchanged screenshot behaviour).
                Rectangle {
                    id: captureButton
                    width: 36
                    height: 36
                    radius: 18
                    color: captureArea.containsMouse
                           ? Qt.alpha(panel.menuWhite, panel.menuHoverButtonOpacity)
                           : Qt.alpha(panel.menuWhite, panel.menuIdleButtonOpacity)
                    border.width: 1
                    border.color: Qt.alpha(panel.menuWhite, panel.menuButtonBorderOpacity)

                    Behavior on color { ColorAnimation { duration: 125 } }

                    Canvas {
                        id: captureIcon
                        anchors.centerIn: parent
                        // The camera outline extends further below the 24px
                        // canvas midpoint; lift it 1px for optical centering.
                        anchors.verticalCenterOffset: -1
                        width: 24
                        height: 24
                        scale: 0.76
                        readonly property color iconColor: panel.menuWhite
                        onIconColorChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = String(iconColor)
                            ctx.lineWidth = 1.6
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            // Compact camera outline.
                            ctx.moveTo(5, 8)
                            ctx.lineTo(8, 8)
                            ctx.lineTo(10, 5.5)
                            ctx.lineTo(16, 5.5)
                            ctx.lineTo(18, 8)
                            ctx.lineTo(20, 8)
                            ctx.quadraticCurveTo(22, 8, 22, 10)
                            ctx.lineTo(22, 19)
                            ctx.quadraticCurveTo(22, 21, 20, 21)
                            ctx.lineTo(4, 21)
                            ctx.quadraticCurveTo(2, 21, 2, 19)
                            ctx.lineTo(2, 10)
                            ctx.quadraticCurveTo(2, 8, 4, 8)
                            ctx.closePath()
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(12, 14.5, 3.4, 0, Math.PI * 2)
                            ctx.stroke()
                        }
                    }

                    MouseArea {
                        id: captureArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.saveSelection()
                    }
                }
            }
        }

        // The only contextual action in OCR mode: copy the words selected
        // with the mouse directly on the frozen screenshot. The original
        // toolbar remains available and the OCR button acts as a toggle.
        Item {
            id: copyTextAction
            readonly property bool hasText: panel.ocrAnchor >= 0 && panel.ocrEnd >= 0
            visible: panel.visible && panel.hasSelection && panel.textMode
                     && panel.ocrReady && hasText && !panel.ocrDragging
                     && !panel.saving
            width: 132
            height: 36

            // Keep the action beside the selection cursor, inside the screen.
            // Prefer below the pointer; flip above near the bottom edge.
            x: Math.max(12, Math.min(panel.width - width - 12,
                                    panel.ocrPointerX + 14))
            y: panel.ocrPointerY + height + 18 < panel.height
               ? panel.ocrPointerY + 12
               : Math.max(12, panel.ocrPointerY - height - 12)

            // Shared GlassSurface material, with compositor blur behind it.


            Rectangle {
                anchors.fill: parent
                radius: copyTextAction.height / 2
                color: Qt.alpha(panel.menuTint, panel.menuOpacity)
                border.width: panel.menuBorderWidth
                border.color: Qt.alpha(panel.menuWhite, panel.menuBorderOpacity)

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: parent.radius / 2
                        rightMargin: parent.radius / 2
                    }
                    height: 1
                    color: Qt.alpha(panel.menuWhite, panel.menuHighlightOpacity)
                }
            }

            // Same subtle interactive hover treatment as the Launcher buttons.
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: copyTextMouse.containsMouse
                       ? Qt.alpha(panel.menuWhite, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 125 } }
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                // Small vector copy icon (no dependency on icon fonts).
                Canvas {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17
                    height: 17
                    readonly property color iconColor: panel.menuWhite
                    onIconColorChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.lineWidth = 1.5
                        ctx.lineJoin = "round"
                        ctx.strokeStyle = String(iconColor)
                        ctx.beginPath()
                        ctx.moveTo(7, 4)
                        ctx.lineTo(13, 4)
                        ctx.quadraticCurveTo(15, 4, 15, 6)
                        ctx.lineTo(15, 13)
                        ctx.quadraticCurveTo(15, 15, 13, 15)
                        ctx.lineTo(7, 15)
                        ctx.quadraticCurveTo(5, 15, 5, 13)
                        ctx.lineTo(5, 6)
                        ctx.quadraticCurveTo(5, 4, 7, 4)
                        ctx.closePath()
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(3, 12)
                        ctx.lineTo(2.5, 12)
                        ctx.quadraticCurveTo(1.5, 12, 1.5, 11)
                        ctx.lineTo(1.5, 3)
                        ctx.quadraticCurveTo(1.5, 1.5, 3, 1.5)
                        ctx.lineTo(11, 1.5)
                        ctx.stroke()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.copyStatus === "Copied to clipboard" ? "Copied!"
                          : (panel.copyStatus === "Copy failed" ? "Copy failed" : "Copy text")
                    color: panel.menuWhite
                    font.family: panel.menuFont
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                id: copyTextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !copyProcess.running
                onClicked: panel.copyRecognizedText()
            }
        }

        // Minimal feedback while Tesseract works, or when it finds no text.
        // No recognized text is duplicated over the screenshot or in a panel.
        Item {
            id: ocrStatus
            visible: panel.hasSelection && panel.textMode && !panel.saving
                     && (panel.ocrBusy || panel.ocrError.length > 0)
            width: Math.min(panel.width - 24, statusLabel.implicitWidth + 28)
            height: 32
            x: Math.max(12, Math.min(panel.width - width - 12,
                                    actions.x + (actions.width - width) / 2))
            y: actions.y + actions.height + height + 8 < panel.height
               ? actions.y + actions.height + 8
               : Math.max(12, actions.y - height - 8)
            // Shared GlassSurface material, with compositor blur behind it.


            Rectangle {
                anchors.fill: parent
                radius: ocrStatus.height / 2
                color: Qt.alpha(panel.menuTint, panel.menuOpacity)
                border.width: panel.menuBorderWidth
                border.color: Qt.alpha(panel.menuWhite, panel.menuBorderOpacity)

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: parent.radius / 2
                        rightMargin: parent.radius / 2
                    }
                    height: 1
                    color: Qt.alpha(panel.menuWhite, panel.menuHighlightOpacity)
                }
            }

            Text {
                id: statusLabel
                anchors.centerIn: parent
                text: panel.ocrBusy ? "Recognizing text…" : panel.ocrError
                color: panel.menuWhite
                font.family: panel.menuFont
                font.pixelSize: 11
            }
        }
    } // menuWindow
}
