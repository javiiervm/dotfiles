import QtQuick
import Quickshell.Io
import "." as Local

// Tarjeta de clima. Usa wttr.in en formato JSON (?format=j1) porque no
// requiere API key. Si prefieres OpenWeatherMap u otro proveedor con más
// precisión, cambia el comando en `Process.command` y el parseo en
// `onStdoutParsed` — la interfaz visual no necesita tocarse.
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
        // -s silencioso, -S ignora errores de cert si tu sistema tiene relojes
        // desincronizados justo tras un boot en frío
        command: ["curl", "-s", "https://wttr.in/?format=j1"]
        stdout: SplitParser {
            splitMarker: "" // recibe el bloque completo
            onRead: data => {
                try {
                    const j = JSON.parse(data)
                    const cur = j.current_condition[0]
                    root.condition = cur.weatherDesc[0].value
                    root.tempC = cur.temp_C
                    root.feelsLike = cur.FeelsLikeC
                    root.high = j.weather[0].maxtempC
                    root.low = j.weather[0].mintempC
                } catch (e) {
                    root.condition = "Sin datos"
                }
            }
        }
    }

    Timer {
        interval: 10 * 60 * 1000 // refresca cada 10 minutos
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    content: Column {
        anchors.fill: parent
        spacing: 6

        Text {
            text: root.condition
            color: "#9fb3c8"
            font.pixelSize: 13
            font.family: "JetBrains Mono Nerd Font"
        }
        Text {
            text: root.tempC + "°C"
            color: "#eef4fb"
            font.pixelSize: 34
            font.weight: Font.Bold
            font.family: "JetBrains Mono Nerd Font"
        }
        Text {
            text: "Feels like " + root.feelsLike + "°C"
            color: "#7f93a8"
            font.pixelSize: 11
            font.family: "JetBrains Mono Nerd Font"
        }
        Text {
            text: "High " + root.high + "°C · Low " + root.low + "°C"
            color: "#7f93a8"
            font.pixelSize: 11
            font.family: "JetBrains Mono Nerd Font"
        }
    }
}
