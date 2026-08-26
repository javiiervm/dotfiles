import QtQuick
import "." as Local
import "../../"

Local.Card {
    id: root

    implicitWidth: 290 * Theme.scale
    implicitHeight: 150 * Theme.scale

    radius: 20 * Theme.scale

    property string condition: "—"
    property string tempC: "--"
    property string feelsLike: "--"
    property string high: "--"
    property string low: "--"
    property string weatherIcon: "☁"

    function getWeatherIcon(desc) {
        let d = desc.toLowerCase()

        if (d.includes("thunder") || d.includes("storm"))
            return "⛈"

        if (d.includes("rain") || d.includes("drizzle"))
            return "🌧"

        if (d.includes("snow") || d.includes("ice"))
            return "❄"

        if (d.includes("clear") || d.includes("sun"))
            return "☀"

        if (d.includes("cloud") || d.includes("overcast"))
            return "☁"

        return "⛅"
    }

    function fetchWeather() {
        var xhr = new XMLHttpRequest()

        xhr.open("GET", "https://wttr.in/?format=j1")

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const j = JSON.parse(xhr.responseText)
                        const cur = j.current_condition[0]

                        root.condition =
                            cur.weatherDesc[0].value

                        root.tempC =
                            cur.temp_C

                        root.feelsLike =
                            cur.FeelsLikeC

                        root.high =
                            j.weather[0].maxtempC

                        root.low =
                            j.weather[0].mintempC

                        root.weatherIcon =
                            getWeatherIcon(root.condition)

                    } catch (e) {
                        root.condition = "Weather unavailable"
                    }
                } else {
                    root.condition = "Weather unavailable"
                }
            }
        }

        xhr.send()
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered:
            root.fetchWeather()
    }

    content: Item {
        anchors.fill: parent

        // ============================================================
        // CONDITION
        // ============================================================

        Text {
            id: conditionText

            anchors.top: parent.top
            anchors.left: parent.left

            text: root.condition

            color: Qt.alpha(Theme.white, 0.88)

            font.family: Theme.fontMain
            font.pixelSize: 14 * Theme.scale
            font.weight: Font.DemiBold
        }

        // ============================================================
        // MAIN TEMPERATURE
        // ============================================================

        Row {
            id: mainWeather

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            spacing: 12 * Theme.scale

            Text {
                text: root.tempC + "°"

                color: Theme.white

                font.family: Theme.fontMain
                font.pixelSize: 56 * Theme.scale
                font.weight: Font.Bold

                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.weatherIcon

                color: Theme.white

                font.pixelSize: 34 * Theme.scale

                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ============================================================
        // DETAILS
        // ============================================================

        Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            spacing: 8 * Theme.scale

            Text {
                text: "Feels"

                color: Qt.alpha(Theme.white, 0.55)

                font.family: Theme.fontMain
                font.pixelSize: 10 * Theme.scale
                font.weight: Font.Medium
            }

            Text {
                text: root.feelsLike + "°"

                color: Theme.white

                font.family: Theme.fontMain
                font.pixelSize: 18 * Theme.scale
                font.weight: Font.Bold
            }
        }

        // ============================================================
        // BOTTOM INFO
        // ============================================================

        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom

            spacing: 14 * Theme.scale

            Text {
                text: "H " + root.high + "°"

                color: Qt.alpha(Theme.white, 0.70)

                font.family: Theme.fontMain
                font.pixelSize: 11 * Theme.scale
                font.weight: Font.DemiBold
            }

            Text {
                text: "L " + root.low + "°"

                color: Qt.alpha(Theme.white, 0.70)

                font.family: Theme.fontMain
                font.pixelSize: 11 * Theme.scale
                font.weight: Font.DemiBold
            }
        }
    }
}