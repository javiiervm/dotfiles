import QtQuick
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260 * Theme.scale
    implicitHeight: 150 * Theme.scale

    property string condition: "—"
    property string tempC: "--"
    property string feelsLike: "--"
    property string high: "--"
    property string low: "--"
    property string weatherIcon: "☁"

    function getWeatherIcon(desc) {
        let d = desc.toLowerCase();
        if (d.includes("thunder") || d.includes("storm")) return "⛈";
        if (d.includes("rain") || d.includes("drizzle")) return "🌧";
        if (d.includes("snow") || d.includes("ice")) return "❄";
        if (d.includes("clear") || d.includes("sun")) return "☀";
        if (d.includes("cloud") || d.includes("overcast")) return "☁";
        return "⛅";
    }

    function fetchWeather() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://wttr.in/?format=j1");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        const j = JSON.parse(xhr.responseText);
                        const cur = j.current_condition[0];
                        root.condition = cur.weatherDesc[0].value;
                        root.tempC = cur.temp_C;
                        root.feelsLike = cur.FeelsLikeC;
                        root.high = j.weather[0].maxtempC;
                        root.low = j.weather[0].mintempC;
                        root.weatherIcon = getWeatherIcon(root.condition);
                    } catch (e) {
                        root.condition = "Parse Error";
                    }
                } else {
                    root.condition = "HTTP Error";
                }
            }
        }
        xhr.send();
    }

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchWeather()
    }

    content: Column {
        anchors.centerIn: parent 
        spacing: 6 * Theme.scale

        // Condición
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.condition
            color: Theme.white
            font.pixelSize: 14 * Theme.scale
            font.weight: Font.DemiBold
            font.family: Theme.fontMain
        }

        // Fila para Temperatura + Icono
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12 * Theme.scale

            Text {
                text: root.tempC + "°C"
                color: Theme.white
                font.pixelSize: 42 * Theme.scale
                font.weight: Font.Bold
                font.family: Theme.fontMain
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.weatherIcon
                color: Theme.white
                font.pixelSize: 32 * Theme.scale
                font.family: Theme.fontMain 
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Sensación térmica
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Feels like " + root.feelsLike + "°C"
            color: Theme.white
            font.pixelSize: 12 * Theme.scale
            font.family: Theme.fontMain
        }

        // Máxima y Mínima
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "High " + root.high + "°C · Low " + root.low + "°C"
            color: Theme.white
            font.pixelSize: 12 * Theme.scale
            font.family: Theme.fontMain
        }
    }
}