import QtQuick
import QtQuick.Window
import "modules" as Modules

Window {
    visible: true
    width: 420
    height: 220
    color: "#10131c"
    title: "Test PasswordField — ventana normal, cerrable con X"

    Modules.PasswordField {
        anchors.centerIn: parent
        onUnlocked: console.log(">>> AUTENTICACION CORRECTA <<<")
    }
}
