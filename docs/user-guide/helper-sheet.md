# Helper sheet / Blad voor de helper

Print this page **before** installing. Fill it in **by hand, on paper**, during the installation.
Keep it at home in a safe place, **not** in the computer bag and **not** taped to the screen.
Never store these secrets in a file, a photo, an e-mail or a message.

Druk deze pagina af **vóór** de installatie. Vul ze **met de hand, op papier** in tijdens de
installatie. Bewaar ze thuis op een veilige plek, **niet** in de laptoptas en **niet** op het
scherm geplakt. Bewaar deze geheimen nooit in een bestand, foto, e-mail of bericht.

---

## Wie doet wat? / Who does what?

| | Wie / Who | Waarvoor / What for |
|---|---|---|
| **Beheerder** (administrator) | de helper: familielid, buur, IT'er | updates die niet vanzelf gaan, printers of programma's toevoegen, problemen oplossen |
| **Dagelijkse account** (everyday account) | de gebruiker zelf | alles van elke dag: internet, e-mail, foto's, brieven. Kan het systeem niet per ongeluk stuk maken. |

Updates en het terugzetten na een mislukte update gaan **vanzelf**. De beheerder is zelden nodig.
Updates and rolling back a failed update are **automatic**. The administrator is rarely needed.

---

## 1. Schijfwachtzin / Disk passphrase (LUKS)

Asked by the installer (step 4) and at start-up when the computer cannot unlock itself.
Gevraagd door de installer (stap 4) en bij het opstarten als de computer zichzelf niet kan
ontgrendelen.

**Zonder deze wachtzin zijn de bestanden voor altijd onleesbaar. Niemand kan ze terughalen.**
**Without this passphrase the files are unreadable forever. Nobody can recover them.**

Tip: four unrelated words / vier losse woorden, bv. `tuin fiets oranje piano`.

    Schijfwachtzin / Disk passphrase:

    ______________________________________________________________

---

## 2. Beheerder / Administrator

Created in the installer (step 5, **User Creation**), with **Make this user administrator**
switched on. Leave **Root Account** alone: Kiezel keeps root locked.
Aangemaakt in de installer (stap 5, **Gebruiker aanmaken**), met **Deze gebruiker beheerder
maken** aangevinkt. Laat **Root-account** ongemoeid: Kiezel houdt root vergrendeld.

    Gebruikersnaam / User name:   beheerder   (or / of: ____________________)

    Wachtwoord / Password:        ______________________________________________

Choose a **different** password from the everyday account, at least 12 characters.
Kies een **ander** wachtwoord dan dat van de dagelijkse account, minstens 12 tekens.

---

## 3. Dagelijkse account / Everyday account

Created at first start (Plasma Setup, after the "Goed leesbaar" page), by or with the user.
Aangemaakt bij de eerste start (Plasma Setup, na de pagina "Goed leesbaar"), door of samen met de
gebruiker.

    Naam / Name:                  ______________________________________________

    Gebruikersnaam / User name:   ______________________________________________

The user may prefer to keep this password in their head only. That is fine: the administrator can
set a new one (System Settings > Users).
De gebruiker houdt dit wachtwoord misschien liever alleen in het hoofd. Dat is goed: de beheerder
kan een nieuw instellen (Systeeminstellingen > Gebruikers).

---

## 4. Gegevens / Details

    Datum installatie / Date installed:   ____ / ____ / ________

    Computer (merk, model) / Make, model:  ______________________________________

    Helper (naam, telefoon) / Helper (name, phone): ____________________________

---

## Wat als... / What if...

| Situatie / Situation | Wat doen / What to do |
|---|---|
| Wachtwoord dagelijkse account vergeten / Everyday password forgotten | The administrator logs in and sets a new one (System Settings > Users). |
| Wachtwoord beheerder vergeten / Administrator password forgotten | Everyday use keeps working. A new administrator needs a reinstall (back up the files first). |
| Schijfwachtzin vergeten / Disk passphrase forgotten | **Not recoverable.** Only a reinstall, and the files are lost. That is why this sheet exists. |
| De computer start een oudere versie / The computer starts an older version | Normal after a failed update: Kiezel went back by itself and shows a message. Nothing to do. |
