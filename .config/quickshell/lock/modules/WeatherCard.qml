import QtQuick
import Quickshell.Io
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 150

    property string condition: "—"
    property string tempC: "--"
    property string feelsLike: "--"
    property string high: "--"
    property string low: "--"

    Process {
        id: weatherProc
        command: ["curl", "-s", "https://wttr.in/?format=j1"] //[cite: 20]
        stdout: SplitParser {
            splitMarker: "" 
            onRead: data => {
                try {
                    const j = JSON.parse(data)
                    const cur = j.current_condition[0]
                    root.condition = cur.weatherDesc[0].value
                    root.tempC = cur.temp_C
                    root.feelsLike = cur.FeelsLikeC
                    root.high = j.weather[0].maxtempC
                    root.low = j.weather[0].mintempC //[cite: 20]
                } catch (e) {
                    root.condition = "No data"
                }
            }
        }
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true //[cite: 20]
    }

    content: Column {
        anchors.fill: parent
        spacing: 6

        Text {
            text: root.condition
            color: Theme.grey1
            font.pixelSize: 13
            font.family: Theme.fontMain
        }
        Text {
            text: root.tempC + "°C" //[cite: 20]
            color: Theme.white
            font.pixelSize: 34
            font.weight: Font.Bold
            font.family: Theme.fontMain
        }
        Text {
            text: "Feels like " + root.feelsLike + "°C" //[cite: 20]
            color: Theme.grey1
            font.pixelSize: 11
            font.family: Theme.fontMain
        }
        Text {
            text: "High " + root.high + "°C · Low " + root.low + "°C" //[cite: 20]
            color: Theme.grey1
            font.pixelSize: 11
            font.family: Theme.fontMain
        }
    }
}