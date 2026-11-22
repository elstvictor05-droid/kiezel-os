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

### Inloggen als beheerder / Logging in as the administrator

The login screen shows **only the everyday account**. The administrator is hidden on purpose, so
the user never picks the wrong account.
Het loginscherm toont **alleen de dagelijkse account**. De beheerder is bewust verborgen, zodat de
gebruiker nooit de verkeerde account kiest.

1. Op het loginscherm: klik onderaan op **Overig…** / On the login screen, click **Other…** at
   the bottom.
2. Typ de gebruikersnaam van de beheerder (hierboven, bv. `beheerder`) / Type the administrator's
   user name (above, e.g. `beheerder`).
3. Typ het beheerderswachtwoord en druk op Enter / Type the administrator password, press Enter.
4. Klaar? Meld af (menu > **Afmelden**). Het loginscherm toont daarna weer de dagelijkse account.
   Done? Log out (menu > **Log Out**). The login screen shows the everyday account again.

For most tasks you do **not** need to log in as the administrator: when the everyday account asks
for something that needs it, a window asks for the administrator password ("Beheerder"). Type it
there and the user stays logged in.
Voor de meeste taken hoeft u **niet** als beheerder in te loggen: vraagt de dagelijkse account iets
waarvoor het nodig is, dan vraagt een venster het beheerderswachtwoord ("Beheerder"). Typ het daar;
de gebruiker blijft ingelogd.

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
| Wachtwoord dagelijkse account vergeten / Everyday password forgotten | The administrator logs in through **Other…** and sets a new one (System Settings > Users). |
| De beheerder staat niet op het loginscherm / The administrator is not on the login screen | Normal: click **Other…** and type the user name (section 2). |
| Wachtwoord beheerder vergeten / Administrator password forgotten | Everyday use keeps working. A new administrator needs a reinstall (back up the files first). |
| Schijfwachtzin vergeten / Disk passphrase forgotten | **Not recoverable.** Only a reinstall, and the files are lost. That is why this sheet exists. |
| De computer start een oudere versie / The computer starts an older version | Normal after a failed update: Kiezel went back by itself and shows a message. Nothing to do. |
