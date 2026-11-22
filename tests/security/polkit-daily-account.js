#!/usr/bin/env node
// Owner requirement (Phase 3, decision 1a): the DAILY account can never get administrator powers,
// neither through the "wheel" group nor around it through a polkit rule.
//
// A live `pkcheck` over SSH evaluates an inactive, remote subject, which is not the case that
// matters. This evaluates EVERY polkit rule and action of the image for the worst case instead: the
// daily account, logged in at the keyboard (active, local), with exactly the groups Plasma Setup
// gives it (from /etc/xdg/plasmasetuprc). Rules run in an isolated JS context the way polkitd runs
// them: files from /etc/polkit-1/rules.d and /usr/share/polkit-1/rules.d ordered by file name
// (/etc wins on the same name), the first non-"not handled" answer counts, otherwise the action's
// <allow_active> default.
//
// FAIL when:
//   - an action whose own default needs an administrator (auth_admin*) is answered with yes or a
//     self-authentication by a rule, unless it is on the reviewed allowlist below; or
//   - one of the CORE admin actions does not need an administrator; or
//   - a CORE action no longer exists (stale list).
//
// Usage: polkit-daily-account.js <image-root> <comma-separated-groups>
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const [root, groupArg] = process.argv.slice(2);
if (!root || groupArg === undefined) {
    console.error("usage: polkit-daily-account.js <image-root> <groups>");
    process.exit(2);
}
const user = "dagelijks";
const groups = [user, ...groupArg.split(",").map((g) => g.trim()).filter(Boolean)];

// Reviewed exceptions: a rule allows these without an administrator, and that is acceptable.
const ALLOW = {
    "org.projectatomic.rpmostree1.upgrade":
        "update to the same signed Kiezel image (signature enforced by policy.json); no rebase",
    "org.projectatomic.rpmostree1.repo-refresh": "refresh metadata only",
};

// Must ALWAYS need an administrator for the daily account.
const CORE = [
    "org.freedesktop.systemd1.manage-units",
    "org.freedesktop.systemd1.manage-unit-files",
    "org.freedesktop.policykit.exec",
    "org.freedesktop.accounts.user-administration",
    "org.projectatomic.rpmostree1.rebase",
    "org.projectatomic.rpmostree1.deploy",
    "org.projectatomic.rpmostree1.install-uninstall-packages",
    "org.projectatomic.rpmostree1.override",
    "org.projectatomic.rpmostree1.rollback",
    "org.freedesktop.Flatpak.configure-remote",   // adding/changing a Flatpak source
    "org.freedesktop.Flatpak.app-install",
    "org.freedesktop.fwupd.update-internal",
    "org.freedesktop.udisks2.modify-device-system",
    "org.kiezel.printer-discovery",
    "org.kiezel.dns-mode",
];

const ADMIN = new Set(["auth_admin", "auth_admin_keep", "no"]);
const ESCALATED = new Set(["yes", "auth_self", "auth_self_keep"]);

// --- actions and their <allow_active> defaults ---------------------------------------------
const actions = {};
for (const dir of ["usr/share/polkit-1/actions", "etc/polkit-1/actions"]) {
    const d = path.join(root, dir);
    if (!fs.existsSync(d)) continue;
    for (const f of fs.readdirSync(d).filter((x) => x.endsWith(".policy"))) {
        const xml = fs.readFileSync(path.join(d, f), "utf8");
        for (const m of xml.matchAll(/<action\s+id="([^"]+)"[\s\S]*?<\/action>/g)) {
            const a = /<allow_active>\s*([a-z_]+)\s*<\/allow_active>/.exec(m[0]);
            actions[m[1]] = a ? a[1] : "no";
        }
    }
}

// --- rules, in polkitd's order --------------------------------------------------------------
const files = new Map();
for (const dir of ["usr/share/polkit-1/rules.d", "etc/polkit-1/rules.d"]) {   // /etc overrides
    const d = path.join(root, dir);
    if (!fs.existsSync(d)) continue;
    for (const f of fs.readdirSync(d).filter((x) => x.endsWith(".rules"))) files.set(f, path.join(d, f));
}
const ruleFns = [];
const Result = { NO: "no", YES: "yes", AUTH_SELF: "auth_self", AUTH_SELF_KEEP: "auth_self_keep",
                 AUTH_ADMIN: "auth_admin", AUTH_ADMIN_KEEP: "auth_admin_keep", NOT_HANDLED: undefined };
for (const name of [...files.keys()].sort()) {
    const polkit = {
        Result,
        addRule: (fn) => ruleFns.push({ name, fn }),
        addAdminRule: () => {},
        log: () => {},
        spawn: () => { throw new Error("spawn not available in the evaluator"); },
    };
    try {
        vm.runInNewContext(fs.readFileSync(files.get(name), "utf8"), { polkit }, { filename: name });
    } catch (e) {
        console.log(`WARN  rule file ${name} could not be loaded: ${e.message}`);
    }
}

const subject = {
    user, pid: 4242, seat: "seat0", session: "c1", local: true, active: true,
    groups,
    isInGroup: (g) => groups.includes(g),
    isInNetGroup: () => false,
};
function evaluate(id) {
    const action = { id, lookup: () => undefined };
    for (const { name, fn } of ruleFns) {
        let r;
        try { r = fn(action, subject); } catch (e) { continue; }   // polkitd logs and continues
        if (r !== undefined && r !== null && r !== "not_handled") return { result: String(r), by: name };
    }
    return { result: actions[id], by: "default" };
}

let fails = 0;
const fail = (msg) => { console.log(`FAIL  ${msg}`); fails++; };
console.log(`subject: ${user}, groups [${groups.join(", ")}], active local session`);
console.log(`evaluated ${Object.keys(actions).length} actions against ${ruleFns.length} rules`);

for (const [id, def] of Object.entries(actions)) {
    if (!def.startsWith("auth_admin")) continue;
    const { result, by } = evaluate(id);
    if (ESCALATED.has(result)) {
        if (ALLOW[id]) console.log(`OK    ${id} -> ${result} (${by}); allowed: ${ALLOW[id]}`);
        else fail(`${id}: default ${def}, but rule ${by} answers ${result} (polkit bypass)`);
    }
}
for (const id of CORE) {
    if (!(id in actions)) { fail(`${id}: core action no longer exists (update the list)`); continue; }
    const { result, by } = evaluate(id);
    if (!ADMIN.has(result)) fail(`${id}: core admin action answered ${result} by ${by}`);
}
if (fails === 0) console.log(`PASS  the daily account cannot get administrator powers through polkit (${CORE.length} core actions need an admin; no unreviewed rule bypass)`);
process.exit(fails ? 1 : 0);
