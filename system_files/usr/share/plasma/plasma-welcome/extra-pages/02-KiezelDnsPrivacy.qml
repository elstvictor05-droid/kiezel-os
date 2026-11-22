// Kiezel Welcome Center page: the DNS privacy trade-off, made visible (owner decision, ADR-0012).
// Default: Quad9 (encrypted when possible) with automatic fallback to the network's DNS.
// The switch: the network's own DNS only (ujust kiezel-dns-router). /usr/libexec/kiezel/dns-mode.
//
// Layout: the page header of Plasma Welcome does not scroll, so everything lives in our own
// ScrollView, with the choice right after one short sentence (reachable with large text).
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

    property string mode: "quad9"

    function refresh() {
        Controller.runCommand("/usr/libexec/kiezel/dns-mode status", (status, output) => {
            const m = /mode: (\w+)/.exec(output)
            root.mode = m ? m[1] : "quad9"
        })
    }
    Component.onCompleted: refresh()

    function setMode(newMode) {
        Controller.runCommand("pkexec /usr/libexec/kiezel/dns-mode " + newMode, (status, output) => root.refresh())
    }

    heading: t("Wie zoekt uw webadressen op?", "Who looks up your web addresses?")
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
                text: root.t("Wie webadressen voor u opzoekt, ziet <b>welke websites</b> u bezoekt. Twijfelt u? Laat het zoals het is.",
                             "Whoever looks up web addresses for you sees <b>which websites</b> you visit. Not sure? Leave it as it is.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.bold: true
                text: root.mode === "router" ? root.t("Nu: uw internetprovider (het netwerk zelf) zoekt op.", "Now: your internet provider (the network itself) does the lookups.")
                    : root.mode === "strict" ? root.t("Nu: alleen versleuteld (Geavanceerd), zonder terugval.", "Now: encrypted only (Advanced), without fallback.")
                    : root.t("Nu: Quad9 zoekt op (aanbevolen).", "Now: Quad9 does the lookups (recommended).")
            }
            QQC2.Button {
                visible: root.mode !== "quad9"
                icon.name: "security-high"
                text: root.t("Quad9 gebruiken (aanbevolen)", "Use Quad9 (recommended)")
                onClicked: root.setMode("quad9")
            }
            QQC2.Button {
                visible: root.mode !== "router"
                icon.name: "network-server"
                text: root.t("Liever mijn internetprovider laten opzoeken", "I prefer my internet provider to do the lookups")
                onClicked: root.setMode("router")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.t("<b>Wat is dit?</b> Als u een website bezoekt, vraagt uw computer eerst op waar die website staat (DNS). Wie dat opzoekt, ziet welke websites u bezoekt, maar niet wat u er doet.<br/><br/>"
                             + "<b>Kiezel gebruikt standaard Quad9</b>, een organisatie zonder winstoogmerk in Zwitserland die zegt geen IP-adressen te bewaren. Waar het kan, gaat de vraag versleuteld; dan ziet uw internetprovider niet welke websites u opzoekt, Quad9 wel. Dat is een kwestie van vertrouwen, geen technische garantie.<br/><br/>"
                             + "Werkt Quad9 niet (bijvoorbeeld bij hotel-wifi met een inlogpagina), dan gebruikt Kiezel vanzelf het netwerk zelf, en daarna weer Quad9.<br/><br/>"
                             + "Later wijzigen kan met: ujust kiezel-dns-quad9 of ujust kiezel-dns-router",
                             "<b>What is this?</b> When you visit a website, your computer first looks up where that website is (DNS). Whoever does the lookup sees which websites you visit, but not what you do there.<br/><br/>"
                             + "<b>Kiezel uses Quad9 by default</b>, a non-profit organisation in Switzerland that says it does not keep IP addresses. Where possible, the lookup is encrypted; your internet provider then cannot see which websites you look up, Quad9 can. That is a matter of trust, not a technical guarantee.<br/><br/>"
                             + "If Quad9 does not work (for example on hotel Wi-Fi with a login page), Kiezel automatically uses the network itself, and then Quad9 again.<br/><br/>"
                             + "You can change it later with: ujust kiezel-dns-quad9 or ujust kiezel-dns-router")
            }
        }
    }
}
