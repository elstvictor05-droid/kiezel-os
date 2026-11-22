// Kiezel first-start page: text size, contrast and screen reader, BEFORE anything else, so the
// rest of Plasma Setup is already readable. Choices are applied immediately and carried into the
// new account through kdeglobals (see /usr/libexec/kiezel/a11y-apply). ADR-0007.
//
// Strings are bilingual (Dutch for nl* locales, English otherwise) so the page needs no separate
// translation catalogue. Plasma Setup's language page comes after this one; the installer has
// already set the system language (nl_BE by default).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasmasetup.components as PlasmaSetupComponents

PlasmaSetupComponents.SetupModule {
    id: root

    readonly property bool dutch: Qt.locale().name.startsWith("nl")
    function t(nl, en) { return dutch ? nl : en }

    property string textSize: "large"
    property string contrast: "normal"
    property bool screenReader: false

    function apply(args) {
        executable.connectSource("/usr/libexec/kiezel/a11y-apply " + args)
    }

    // Large text is the default for Kiezel: applied as soon as the page appears.
    Component.onCompleted: apply("text " + textSize)

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    nextEnabled: true

    component BigChoice: QQC2.Button {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        checkable: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        Accessible.role: Accessible.RadioButton
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            text: root.t("Goed leesbaar", "Easy to read")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: root.t("Kies wat voor u het prettigst leest. U kunt dit later altijd nog veranderen in Systeeminstellingen.",
                         "Choose what is most comfortable to read. You can always change this later in System Settings.")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Kirigami.Heading {
            level: 2
            text: root.t("Tekstgrootte", "Text size")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.ButtonGroup { id: sizeGroup }
            Repeater {
                model: [
                    { key: "normal", nl: "Normaal", en: "Normal" },
                    { key: "large", nl: "Groot", en: "Large" },
                    { key: "xlarge", nl: "Extra groot", en: "Extra large" }
                ]
                delegate: BigChoice {
                    required property var modelData
                    text: root.t(modelData.nl, modelData.en)
                    QQC2.ButtonGroup.group: sizeGroup
                    checked: root.textSize === modelData.key
                    onClicked: { root.textSize = modelData.key; root.apply("text " + modelData.key) }
                }
            }
        }

        Kirigami.Heading {
            level: 2
            text: root.t("Kleuren", "Colours")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.ButtonGroup { id: contrastGroup }
            BigChoice {
                text: root.t("Normaal", "Normal")
                QQC2.ButtonGroup.group: contrastGroup
                checked: root.contrast === "normal"
                onClicked: { root.contrast = "normal"; root.apply("contrast normal") }
            }
            BigChoice {
                text: root.t("Hoog contrast (wit op zwart)", "High contrast (white on black)")
                QQC2.ButtonGroup.group: contrastGroup
                checked: root.contrast === "high"
                onClicked: { root.contrast = "high"; root.apply("contrast high") }
            }
        }

        Kirigami.Heading {
            level: 2
            text: root.t("Voorlezen", "Read aloud")
        }
        BigChoice {
            id: readerButton
            icon.name: "preferences-desktop-text-to-speech"
            text: root.screenReader ? root.t("Voorlezen staat AAN (klik om uit te zetten)", "Reading aloud is ON (click to turn off)")
                                    : root.t("Lees het scherm voor", "Read the screen aloud")
            checked: root.screenReader
            Accessible.role: Accessible.CheckBox
            onClicked: { root.screenReader = !root.screenReader; root.apply("reader " + (root.screenReader ? "on" : "off")) }
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: root.t("Sneltoets: Meta + Alt + S zet voorlezen aan of uit. Meta + = en Meta + − vergroten en verkleinen het scherm.",
                         "Shortcut: Meta + Alt + S turns reading aloud on or off. Meta + = and Meta + − zoom the screen in and out.")
            wrapMode: Text.Wrap
            opacity: 0.8
        }
    }
}
