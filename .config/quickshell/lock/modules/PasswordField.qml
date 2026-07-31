import QtQuick
import Quickshell.Services.Pam

// Campo de contraseña translúcido con autenticación PAM real.
//
// Flujo real de PamContext (verificado contra
// /usr/lib/qt6/qml/Quickshell/Services/Pam/quickshell-service-pam.qmltypes):
//   1. start()               → inicia la sesión PAM (sin argumentos)
//   2. señal pamMessage      → el backend pide algo; mirar las propiedades
//                              `message` / `responseRequired` / `responseVisible`
//   3. respond(texto)        → responder cuando responseRequired es true
//   4. señal completed(result) → PamResult.Success / Failed / Error / MaxTries
//
// `config` y `user` no se fijan explícitamente: por defecto ya usa el
// servicio "login" de /etc/pam.d y el usuario del proceso actual, que es
// lo que confirmó tu log ("Starting pam session for user javier with
// config login").
Item {
    id: root
    implicitWidth: 260
    implicitHeight: 46

    signal unlocked()

    property bool authenticating: false
    property string errorText: ""

    PamContext {
        id: pam

        onPamMessage: {
            // El backend está pidiendo algo (típicamente la contraseña).
            // Le respondemos con lo que el usuario ha escrito.
            if (responseRequired) {
                pam.respond(field.text)
            }
        }

        onCompleted: result => {
            root.authenticating = false
            if (result === PamResult.Success) {
                root.errorText = ""
                root.unlocked()
            } else {
                root.errorText = "Contraseña incorrecta"
                field.text = ""
                shake.start()
            }
        }

        onError: error => {
            root.authenticating = false
            root.errorText = "Error PAM: " + PamError.toString(error)
            field.text = ""
        }
    }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: 23
        color: "#00000033"
        border.width: 1
        border.color: "#ffffff26"

        SequentialAnimation {
            id: shake
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: -8; duration: 40 }
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 8; duration: 40 }
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 8

            Text {
                text: ""
                color: "#eef4fb"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
            }

            TextInput {
                id: field
                width: parent.width - 70
                anchors.verticalCenter: parent.verticalCenter
                echoMode: TextInput.Password
                color: "#eef4fb"
                font.pixelSize: 14
                font.family: "JetBrains Mono Nerd Font"
                focus: true
                enabled: !root.authenticating

                Text {
                    text: root.errorText !== "" ? root.errorText : "Enter your password"
                    color: root.errorText !== "" ? "#ff8080" : "#7f93a8"
                    font.pixelSize: 13
                    font.family: "JetBrains Mono Nerd Font"
                    visible: field.text.length === 0
                }

                onAccepted: {
                    if (text.length === 0 || root.authenticating) return
                    root.authenticating = true
                    root.errorText = ""
                    pam.start()
                }
            }

            Text {
                text: ""
                color: "#eef4fb"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; onClicked: field.accepted() }
            }
        }
    }
}
