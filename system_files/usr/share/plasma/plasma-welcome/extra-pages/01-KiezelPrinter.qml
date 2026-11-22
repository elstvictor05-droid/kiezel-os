// Kiezel Welcome Center page: "Do you have a network printer at home?" (owner decision, Phase 2a).
// Printer discovery (mDNS) is closed by default. "Yes" puts ONLY the current network in the
// firewall zone kiezel-home; public Wi-Fi elsewhere keeps the closed default zone.
// docs/hardening.md §3, /usr/libexec/kiezel/printer-discovery.
//
// Layout: the page header of Plasma Welcome does not scroll, so everything lives in our own
// ScrollView, with the buttons right after one short sentence (reachable with large text).
// Bilingual strings (Dutch for nl* locales, English otherwise): no translation catalogue needed.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import org.kde.plasma.welcome

Page {
    id: root

    readonly property bool dutch: Qt.locale().name.startsWith("nl")
    function t(nl, en) { return dutch ? nl : en }

    property bool homeNetwork: false

    function refresh() {
        Controller.runCommand("/usr/libexec/kiezel/printer-discovery status", (status, output) => {
            // Trust what the firewall applies, not only what is configured.
            root.homeNetwork = status === 0 && output.indexOf("firewall=kiezel-home") !== -1
        })
    }
    Component.onCompleted: refresh()

    heading: t("Heeft u een netwerkprinter thuis?", "Do you have a network printer at home?")
    description: ""

    QQC2.ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.t("Een printer via wifi of netwerkkabel kan Kiezel vanzelf vinden. <b>Doe dit alleen thuis</b>, niet op openbare wifi.",
                             "Kiezel can find a printer on Wi-Fi or a network cable by itself. <b>Only do this at home</b>, not on public Wi-Fi.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.bold: true
                text: root.homeNetwork
                      ? root.t("✓ Dit netwerk staat ingesteld als thuisnetwerk: printers worden gevonden.", "✓ This network is set as your home network: printers are found.")
                      : root.t("Dit netwerk is nu niet zichtbaar voor printers.", "This network is currently not visible to printers.")
            }
            QQC2.Button {
                visible: !root.homeNetwork
                icon.name: "printer"
                text: root.t("Ja, dit is mijn thuisnetwerk: zoek printers", "Yes, this is my home network: find printers")
                onClicked: Controller.runCommand("pkexec /usr/libexec/kiezel/printer-discovery on", (status, output) => {
                    root.refresh()
                    if (status === 0) root.showPassiveNotification(root.t("Printers op dit netwerk worden nu gevonden.", "Printers on this network are now found."))
                })
            }
            QQC2.Button {
                visible: root.homeNetwork
                icon.name: "network-wireless-disconnected"
                text: root.t("Toch niet: maak dit netwerk weer onzichtbaar", "Undo: make this network invisible again")
                onClicked: Controller.runCommand("pkexec /usr/libexec/kiezel/printer-discovery off", (status, output) => root.refresh())
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.t("<b>Waarom alleen thuis?</b> Om printers te vinden moet uw computer zichtbaar zijn op het netwerk. Kiezel onthoudt dit alleen voor <b>dit</b> netwerk; op andere netwerken (station, hotel, café) blijft uw computer onzichtbaar.<br/><br/>"
                             + "Een printer met een USB-kabel werkt altijd, daarvoor hoeft u niets te doen.<br/><br/>"
                             + "Geen netwerkprinter, of niet thuis? Klik dan gewoon op Volgende. Later kan het nog met: ujust kiezel-printer-discovery",
                             "<b>Why only at home?</b> To find printers, your computer has to be visible on the network. Kiezel remembers this only for <b>this</b> network; on other networks (station, hotel, café) your computer stays invisible.<br/><br/>"
                             + "A printer with a USB cable always works; you do not need to do anything for that.<br/><br/>"
                             + "No network printer, or not at home? Just click Next. You can still do it later with: ujust kiezel-printer-discovery")
            }
        }
    }
}
