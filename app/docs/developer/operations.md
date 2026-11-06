---
title: Instance operations
description: Who an operator is, how the first one comes to exist, what the operations area can and cannot do, and the security posture around it
keywords: operator operations admin instance bootstrap invite-only suspend lock workspace activity owner
---

# Instance operations

An **operator** administers the whole instance from above the workspaces:
creating and locking workspaces, looking users up, granting other operators,
and reading activity across every workspace. Operators are ordinary users
with an `Operatorship` row — nothing else marks them out, and holding one
does not make them a member of anything. The operations area never opens a
workspace the way a member does; see [Extending: Cross-workspace
queries](extending#cross-workspace-queries), Pattern 4.

## Day one on an invite-only instance

Nobody can reach `/operations` until an operator exists, and both
`operators:grant` and `tenancy:owner_setup_link` abort with "User not found"
if the email has no account yet — so a person must exist first.

Under the `:shared` preset (see [App Presets](presets)) the grant already
happened: the seed gives the bootstrap Owner an operatorship at boot, because
on that preset someone has to be able to create workspaces and see users
before anyone else exists. The seed also gives that account a placeholder
password nobody knows, so you still claim it with the
`tenancy:owner_setup_link` line below — skip only `operators:grant`.

On any other preset, `db:seed` creates no user, so pick the path that matches
your `SIGNUP_MODE`:

- **Signup is open.** Register through the normal flow first
  (`/session/new` → registration magic link → name), then continue below.
- **Signup is invite-only.** Nobody can register yet, so mint the
  account from the console — `User.create!` needs only `email_address`,
  `first_name` and `last_name`; a password is optional. This also runs
  `User#onboard_workspace` like any other signup, so depending on your
  `WORKSPACE_ON_SIGNUP` preset it may hand the new account a personal
  workspace or a shared-workspace membership as a side effect — harmless for
  an operator account, but worth knowing before you're surprised by it in
  the member list.

  ```sh
  bin/rails runner 'User.create!(email_address: "me@example.com", first_name: "Me", last_name: "Operator")'
  ```

These commands run wherever the database is. On a Kamal deploy, `bin/rails` on
your laptop reaches your development database, and production would still have no
account. Use `bin/kamal console` for the `User.create!` line, and
`bin/kamal app exec --reuse "bin/rails 'operators:grant[me@example.com]'"` for the tasks.

Either way, then:

```sh
bin/rails 'operators:grant[me@example.com]'
bin/rails 'tenancy:owner_setup_link[me@example.com]'
```

The quotes matter in zsh, the shell a Mac opens by default: unquoted square
brackets are a glob pattern, and the command stops at "no matches found"
before Rails sees it.

`operators:grant` grants an `Operatorship` (idempotent — running it again
just reports they're already an operator) and records the address as
verified — an operator typed it, the same vouching the `:shared` seed does —
which is what sending invitations requires (`User#can_invite?`); a
console-minted account has no verified address otherwise, and its first
create-for-owner would be refused with "Verify your email address before
sending invitations." When both commands finish the account can sign in,
operate, and invite. `tenancy:owner_setup_link` mints
a short-lived `set_password`-intent sign-in link and **prints it to your
terminal** — it is never emailed, so this step needs no working SMTP even on
an invite-only instance where the open-signup path above does. Opening the
link and confirming signs you in (satisfying the reauthentication the area
force-checks on every request, [below](#how-it-stays-safe)) and lands you on
`/settings/password/new` to set one (when `AUTH_PASSWORDS=enabled`; otherwise
on the signed-in home page); open `/operations` from there, or
navigate there directly while that sign-in is still fresh. If you let the 15-minute
reauth window lapse before setting a password, the next `/operations`
request bounces you to the reauthentication interstitial, and a
still-passwordless account's only factor there is an emailed one-time code —
so set a password in that first window if outbound mail isn't wired up yet.

## What the area does

- **Workspaces** (`/operations/workspaces`) — every kept workspace, locked
  ones included. Open one to see its member list and recent activity, lock
  or unlock it, or create a new one: an existing user's email makes them the
  owner immediately; an unknown email makes *the operator* the interim
  owner and sends that email an ordinary workspace invitation carrying the
  Owner role. See [The operator becomes the owner](#the-operator-becomes-the-owner)
  below — this is deliberate. Creation honors `TENANCY_WORKSPACE_CREATION`
  the same as the tenant-side flow; the operations area does not bypass it.
- **Users** (`/operations/users`) — a paginated list of everyone with an
  account, **newest first**, with a filter over it. The order is `created_at`
  and cannot be a name: names are encrypted non-deterministically, so an SQL
  sort reads ciphertext and a keyed digest is not order-preserving — the only
  SQL-orderable name key would be a plaintext column, which is a security
  decision, not an oversight (see
  [Security: Personal Data at Rest](security#personal-data-at-rest)). The
  filter has two branches for the same reason: an exact match on the
  deterministically-encrypted address, and a bounded decrypt-and-match pass
  over names (`User::Search`, which the activity ledger's search box shares).
  Both caps are stated on the page rather than applied quietly — if there were
  too many accounts to search names, or the match list stopped at its limit,
  it says so. When nothing matches, the page offers the activity ledger's
  search, which also matches workspaces and projects. A user's page opens with their states as badges
  (operator, suspended, sign-in blocked), says since when, and holds every
  control in one row: let a locked-out account try again, or suspend or
  reinstate them (sign-in is refused and sessions end; memberships and roles
  are untouched). A membership in a locked workspace is badged, since that
  is the other reason someone cannot get in. "View activity" opens the
  ledger narrowed to them, and a ledger row's details link back to this
  page. An operator can't be suspended from here — revoke their operator
  access first; `rails users:suspend` is the unguarded break-glass path. See
  [Suspension keeps memberships](#suspension-keeps-memberships) below.
- **Activity** (`/operations/activity_logs`) — every workspace's activity as a
  ledger: newest first, the last 30 days by default, filterable by one search
  box, workspace or the instance level, kind, and date range; sortable by
  time or by workspace name (instance-level rows sit last either way); 25 to
  500 rows a page. The search box resolves an email address, a
  person's name, a workspace or a project, and shows the rows for any of them
  — an email matches exactly (the column is deterministically encrypted),
  everything else matches anywhere in the text. Names are matched after
  decryption in Ruby, the same technique as the members page
  (`ActivityLog::Search`, `WorkspaceRoster` — see
  [Security: Personal Data at Rest](security#personal-data-at-rest)), so they
  are searched only on instances under `User::Search::NAME_SEARCH_LIMIT`
  users (2,000); above that the summary says names were not searched and the
  box answers exact addresses only. Filters apply as you change them. Each row
  opens to the change it recorded, the record it is about, its tier, the
  person's own page, and links that narrow the ledger to that person or to
  that workspace. Controls that must navigate the whole page (sort, rows,
  the pager, a range preset, a pivot) hand focus back to themselves — or to
  the choice just made — in the new document (`data-focus-key`, read by
  `navigation_focus.js`), so a keyboard user is not walked back to the top
  after every sort. Two things the page says on its face and that an
  operator ruling something out must remember: locks and deactivations are
  stored as workspace and member *updates* (filter by those kinds), and rows
  are written best-effort, so an empty result is not proof. Personal security
  events (password changes, passkeys, new devices) never appear here — that
  split is the same `admin` vs. `personal` visibility the rest of the app
  already uses.

  One kind of `admin` row is excluded on top of that split: a suppressed
  invitation delivery. Those rows are the only evidence that a recipient
  blocked an inviter, and on a single-operator instance the operator is
  usually the inviter — so admin visibility alone would hand them a way to
  confirm a block. `ActivityLog::INVITER_UNREADABLE_ACTIONS` names them and
  the feed filters them out. If you add an action whose existence would tell
  an inviter something a recipient chose not to tell them, add it there too.
- **Operators** (`/operations/operatorships`) — who can do all this, and who
  granted them. Granting takes an email that must already belong to a user;
  revoking removes an `Operatorship`, except the last one — see [How it
  stays safe](#how-it-stays-safe).

## What it deliberately does not do

- Act *inside* a workspace. Editing projects, changing settings, inviting
  members — that's a member's job. Grant yourself a membership the ordinary
  way if you need to do it (or, for a workspace you just created for an
  unknown owner, you're already in it).
- Sort the ledger by who acted. Actor names are encrypted with the
  non-deterministic cipher, so SQL cannot order by them, and a sort that
  loads and decrypts the whole result only works under the 500-row cap — a
  header that works on some filters and not others is worse than none. To
  see one person's rows, search for them (the row details offer that pivot);
  time and workspace are the two sorts. The question a Who sort is usually
  reached for — *who has been busiest here* — is answered instead by the
  **Most active** strip above the table: a count per person over whatever
  filter is applied, which states the answer rather than asking you to eyeball
  which alphabetical block is tallest across pages.
- Scope an operator to some workspaces rather than all of them. An
  operator's reach is the whole instance today — `operated_workspaces` is
  every kept workspace, with no notion of "some." A scoped-operator arc that
  narrows this is planned, not built.
- Impersonate a user.
- Find a departed actor. The filters resolve people through `users`, so once
  an account is gone the rows that still carry its name are reachable only by
  scrolling: `actor_name` is encrypted with the non-deterministic cipher, the
  same reason there is no Who sort.

## The Workspace filter changes shape as you grow

On a small instance the Workspace filter is a dropdown of every workspace.
Past `Operations::ActivityLogsController::WORKSPACE_PICKER_LIMIT` (100) it
becomes a search box instead, and the list is not rendered at all.

That switch is automatic, and it is automatic **because you are a fork**. An
operator's reach is every kept workspace on the instance, so the dropdown grew
with your business and was re-sent on every full-page navigation — and sorting
and paging both are. Nobody is watching your instance for the day that starts to
hurt, so the page watches for itself.

What it does *not* do is quietly shorten the list. A workspace missing from a
capped dropdown would be unselectable with nothing on screen to say so, which
trades a slow page for a wrong one. When the search offers more matches than it
shows, it states the number it left out.

Searching is server-side and matches a name fragment or an exact slug.
Workspace names are plaintext, so this is ordinary SQL — unlike people's
names, which are encrypted and searched the slower way described above. A search
matching exactly one workspace applies the filter; several offer you the
choice rather than guessing; none says so.

Ordinary SQL, but not an indexed one: a name *fragment* is a `LIKE '%term%'`,
which no index can serve, so each search examines every kept workspace — about
0.11 ms per thousand, so 11.4 ms at 100,000 workspaces. That is well under the
cost of the encrypted-name pass it sits beside. Past roughly 500,000 tenants,
the answer is prefix matching or FTS5 — a product decision about what a search
means, not a migration.

`?workspace=<slug>` keeps working on both shapes, so links and bookmarks survive
the switch.

## The operator becomes the owner

Creating a workspace for an email with no account doesn't leave that
invitation floating with nobody to receive it: the operator who created the
workspace becomes its owner immediately, and the invited email gets an
ordinary Owner invitation through the same path any workspace invitation
uses. This was deliberate, not an oversight — "invited to nothing" isn't a
state this product has a page for, and routing it through the ordinary
invitation flow means every other page in the app can keep assuming a
workspace always has an owner.

The consequence: until the invited owner accepts, the operator is a real,
tenant-visible member of that workspace, showing up in its member list like
anyone else. Nothing removes them automatically — not on acceptance, not
ever. Hand off deliberately, the same way any owner would: transfer
ownership or leave the workspace once the new owner is in place. An operator
who creates workspaces regularly and never hands off accumulates
memberships this way. That is decided, not outstanding: filtering the switcher
would need membership provenance the schema does not carry, and auto-leaving on
acceptance cannot tell an operator's interim ownership from an owner inviting a
co-owner. If operators are ever scoped to particular workspaces, hand-off stops
being only untidy — a stale interim membership would confer real access rather
than redundant access — so it becomes an acceptance criterion of that arc.

## Suspension keeps memberships

Suspending a user discards nothing: memberships, roles and project access
are all left exactly as they were. A suspended sole owner still owns their
workspace, and reinstating them restores that access with no further
repair. While they're suspended, that workspace simply has no active
owner able to sign in — that's the point of a hold, not a gap in it.

## Who learns about a hold

One rule, applied in all three directions, so there is no per-surface exemption to keep straight:

- **The person, at the moment of impact.** The sign-in attempt that is refused says so. That is the only moment the information is actionable for them.
- **Tenants, never.** A hold is between the operator and that person. Their memberships, roles and rows are untouched, and no workspace-facing surface marks them as held — a member list that showed it would disclose an account-level decision to people with no part in it.
- **Operators, always.** The operations user page names the state, says since when, and holds the controls.

**Mail follows the same rule wherever the app chooses the recipient: a suspended address gets no notification, no digest, and no invitation.** `NotificationMailer` drops any message whose recipient is suspended (`abort_when_recipient_suspended`), which covers workspace notifications and the security notices that ride the same path — password changed, sign-in from a new device — neither of which can occur while sign-in is refused anyway. The digest's candidate scope is `User.not_suspended` (`DigestMailerJob`), so a held account costs no work, and `InvitationMailer#abort_unless_deliverable` skips a suspended address without stamping a suppression row. Mail that answers a request typed at the sign-in screen is the exception: a magic link or a password-reset link **is still sent** to a suspended address (`MagicLinksController#create`, `PasswordResetsController#create`), because those endpoints deliberately answer every address the same way rather than reveal which accounts exist; the link it carries is refused at redemption (`Authenticatable`, `User::SuspendedError`). Withholding security mail is the deliberate part and worth arguing with: a suspended user cannot act on a security notice, because the sign-in that would let them act is exactly what is refused. A reset on reinstatement recovers the same ground through the same address. The alternative — exempting security mail — buys a notification nobody can use in exchange for a second rule and a class of mail that must be kept straight forever.

The same principle settles what an operator's action on a user records: `User::Suspension#suspend!` and `#unsuspend!` write their audit rows at **admin** visibility (`ActivityLog.record_security_event!` with `visibility: "admin"`), so the operations ledger shows them and neither a workspace surface nor the person's own security feed, which reads only personal rows, ever does.

## How it stays safe

- A non-operator gets a 404 on every `/operations` route — the area's
  existence isn't confirmed to them.
- Every request re-checks reauthentication, hard-wired on
  (`force: true`): it fires even for a fork that has turned
  `reauth_enabled` off. This is the app's only surface gated on *every*
  action, GET included, not just mutations — see [Security:
  Re-Authentication](security#re-authentication-sensitive-changes).
- `Operations::` controllers never include `WorkspaceScoped` and never set
  `Current.workspace`; a workspace is reached only through the signed-in
  operator's own reach relation, `Current.user.operated_workspaces`. See
  [Extending: Cross-workspace queries](extending#cross-workspace-queries),
  Pattern 4.
- The last operator can't be revoked from the panel — the roster refuses, so
  an instance can't lock everyone out through the UI. See [Locked out
  (break-glass)](#locked-out-break-glass) below for the server-access path.

  The guard (`Operatorship#revoke_by_operator!`) is atomic under
  concurrency: `BEGIN IMMEDIATE` opens the transaction at the block's first
  statement, so the count runs under the writer lock (`lock!` is only a
  reload on SQLite, not the mechanism) — two operators revoking two
  *different* rows can't both pass the count check and leave zero (the
  lock-then-check shape of every guarded mutator — see [Architecture §
  Concurrency](architecture); a Postgres fork must add an explicit lock). It
  also refuses an operator revoking their own row outright, and checks that
  case AFTER the last-operator one:
  when only one operator remains, that operator is necessarily the one
  attempting the revoke, so `:last_operator` is the more useful refusal — it
  names the break-glass path, where a generic self-revoke refusal would
  point at a second operator who doesn't exist.
- Granting and revoking an operatorship writes an audit row in the same
  transaction as the grant or revoke, and those rows sit behind the
  security retention floor described in [Security: Activity
  Tracking](security#activity-tracking).
- An operator locking or unlocking a workspace shows up in that workspace's
  *own* activity feed too, named as the actor — a tenant owner can see that
  an operator touched their workspace, not just that it happened.

## Locked out (break-glass)

Three rake tasks are the server-access door the panel deliberately can't
open:

```sh
bin/rails operators:list             # who currently operates the instance
bin/rails 'operators:revoke[email]'  # take operator access away
bin/rails 'operators:grant[email]'   # give operator access
```

- **The last operator left, or an instance somehow has none:** `grant` a
  known user directly — it doesn't require an existing operator to run it.
- **An operator lost access** (locked account, gone email, anything short of
  a compromise): `list` to confirm who currently holds it, then `grant` a
  replacement.
- **An operatorship needs to be pulled** (compromise, off-boarding, or just
  cleaning up a stale grant): `revoke`.

`revoke` deliberately has **no** last-operator guard the way the panel does
— it's the break-glass path precisely for the case the panel refuses to
handle, so it always does what you ask.
