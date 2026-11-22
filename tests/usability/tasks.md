# Usability tasks for the two older testers (Phase 3)

Two real older testers each get these tasks on a freshly installed Kiezel PC (the helper has done
the installer part). An observer sits beside them, **does not help**, and writes down where they
hesitate, what they say, and how long each task takes. After both sessions: adjust, then test
again.

Rules for the observer:

- Read each task aloud exactly as written. Do not point at the screen.
- After 3 minutes stuck, note "stuck", give the smallest possible hint, and note the hint.
- Write down the tester's own words when something is unclear ("what does that mean?").
- No names or personal details in the notes: "tester A", "tester B".

| # | Task (read aloud) | Observe | Pass when |
|---|---|---|---|
| S1 | "Turn the computer on and set it up so you can read everything comfortably." | The "Goed leesbaar" page: do they try the bigger text, the voice, the high contrast? | They finish the page and say the text is comfortable |
| S2 | "Make your own account." | Account page, wording "zonder beheerdersrechten" | Account made without help |
| **L1** | "Log in." (at their usual distance from the screen, glasses as usual) | **Login screen text size (now 13 pt, ~28% larger than standard; owner: not final until both testers have judged it).** Can they read their name, the password field and the buttons without leaning in? | Both testers read all three without leaning in. Otherwise: record "too small" and the distance |
| L2 | (same moment) | The administrator is hidden (decision 6a). Do they see exactly one account, theirs? Do they look for anything else? | They pick their own account without hesitating |
| T1 | "Make the text bigger." (after login) | Where do they look? Do they remember the first page? | Text bigger within 3 minutes |
| T2 | "Send an e-mail with a photo to [observer's test address]." | Thunderbird, attaching a file | E-mail received with the photo |
| T3 | "Look up the weather for tomorrow." | Firefox, search | Weather shown |
| T4 | "Print this letter." (only if a printer is present) | The printer welcome page, the admin password prompt | Ask the helper, or the letter prints |
| T5 | "Install a game." | The admin prompt: is it clear they need the helper? Their words | They understand they need the helper (they do not need to succeed) |
| T6 | "Ask for help." | Where do they look? (The "Hulp vragen" route is still being designed) | Record what they try first |
| T7 | "Turn the computer off." | | Off without holding the power button |

After each session, also ask:

1. "Was anything too small to read?" (login screen, menus, windows)
2. "Was anything confusing or scary?"
3. "Would you use this computer on your own?"

Record the answers per tester in `notes/` (not in the repository: notes can contain impressions of
real people).
