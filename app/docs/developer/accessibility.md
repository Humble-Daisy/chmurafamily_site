---
title: Accessibility
description: How this template enforces WCAG 2.2 Level AAA — the axe-core gate, the helpers, and the tracked exclusions
keywords: accessibility wcag aaa axe-core contrast focus target size cuprite system specs dark mode
---

# Accessibility

This template targets **WCAG 2.2 Level AAA** on every screen, and it enforces that target automatically — not by review discipline alone. Accessibility is a build output that can fail CI, the same way a broken test does. New UI is expected to pass at AAA the day it ships.

## What AAA Means Here

Level AAA raises the bar above the more common AA baseline:

| Requirement | AAA standard |
|-------------|--------------|
| Contrast (normal text) | 7:1 |
| Contrast (large text) | 4.5:1 |
| Interactive target size | 44×44px minimum |
| Focus indicator | Always visible, never suppressed |

These are the headline rules the automated gate checks, alongside the rest of the `wcag2aaa` rule set.

## How the Gate Runs

Accessibility is audited with [axe-core](https://github.com/dequelabs/axe-core), injected into the page through Cuprite (Ferrum/CDP) during system specs. The audit runs the **cumulative** WCAG tag set — 2.0 + 2.1 + 2.2 at A/AA/AAA (`AxeAccessibility::AXE_TAG_SET` — the versions are separate axe tags, and listing only the 2.0-era ones silently skips every 2.1/2.2 rule). axe's `target-size` rule (24px, 2.5.8) is explicitly enabled — it ships disabled.

This audit runs automatically after *every* system spec, **everywhere — including locally** — and it audits **both themes**, setting each one explicitly. There is no opt-in to forget. The hook lives in `spec/support/axe_accessibility.rb` and uses `DEFAULT_AXE_OPTIONS`. If any rule fails, the spec fails.

Set `SKIP_AXE=1` to opt out for a fast focused loop (roughly a third quicker on a single file). It is deliberately opt-*out*: the default has to be the safe one.

**The audit cannot be switched off silently.** It once was, for months, without a single red run: a second `Capybara.reset_sessions!` after-hook in `spec/support/capybara.rb` ran ahead of the audit hook, so every example was already on `about:blank` when the audit looked, and it skipped ([#912](https://github.com/dschmura/modelrails_base/issues/912)). Three things now hold it on:

- The audit hook writes a ledger entry for every system example (`:audited`, or `:blank` when the example ended with no page), and a prepended `visit` records which examples navigated. An `after(:suite)` gate raises for any example that navigated without an `:audited` entry, so an inert hook fails the run instead of passing it.
- There is no per-example opt-out tag. A page that has to show an anti-pattern is built to show it accessibly (a non-executing code sample, for instance), not excused from the audit. Narrow-viewport examples assert axe inside their viewport block *and* get the teardown audit at the restored desktop width.
- `spec/code_smells/axe_teardown_audit_is_always_on_spec.rb` refuses a `reset_sessions!` anywhere in `spec/support`, a skip tag anywhere in `spec/`, and `SKIP_AXE` in any workflow that runs specs (the devcontainer provisioning check is the one named exception) or in the Lefthook config. It also reads the support file and requires the per-example hook and the suite gate to stay registered, behind nothing but the `SKIP_AXE` guard, so deleting them is red too. `SKIP_AXE=1` prints a banner at suite start so a shell profile cannot hide it.

> **Why both, and why not CI-only.** Until [#541](https://github.com/dschmura/modelrails_base/issues/541) the hook ran only under `ENV["CI"]` and audited whatever theme the example happened to leave behind. That made the verdict depend on test choreography — the same command would catch a violation on one run and miss it on the next — and it meant a page's dark rendering was audited only if some example happened to leave it dark. A real dark-mode contrast bug reached `main` under a green CI as a result. Dedicated `*_in_both_themes` examples still matter, but they only cover the states *they* set up; the per-example hook is what covers every state your specs already render.

Beyond axe's own rules, every audit also runs (2026-07 gate upgrade):

- **Surfaced `incomplete` contrast**: axe files "can't compute" cases (text
  over an image) as `incomplete`, not violations — the gate fails any
  INTERACTIVE element in that bucket with no opaque background plate
  up-chain.
- **`mc-target-size-44`** — the AAA 44×44 floor (2.5.5), measured as the
  input+label union for form controls. Exceptions: links inside running
  text (the SC's own inline exception), sr-only bypass links, and the
  composite-widget deviation below.
- **`mc-focus-indicator`** — flags focusables whose outline is suppressed
  by author CSS with no `:focus`/`:focus-visible` paint rule matching them
  (2.4.7). Static CSSOM analysis: JS-only highlight schemes will flag and
  need a real focus-state style.
- **`mc-transparent-over-media`** — samples the real paint stack
  (`elementsFromPoint`) and fails any interactive element that hits an
  image/canvas/video before any opaque background. Contrast over a raster
  is unknowable; give the control an opaque plate.
- **`mc-one-h1`** — a whole-page audit of an app page needs exactly one
  rendered `<h1>`. Component previews and the draft harness are exempt, as
  is any audit scoped with `include:`. axe's own `page-has-heading-one` only
  asks for at least one, and it fires on every preview host.

### Documented deviation: composite-widget interiors

Dropdown menu items and listbox options (`role=menuitem|option` inside
`role=menu|menubar|listbox`) keep desktop density and are **not claimed
under 2.5.5** on fine-pointer devices — 2.5.5 has no "dense widget"
exception, so this is an honest deviation, not a reinterpretation. Two
compensations, both enforced: the gate holds those items to the **24px
2.5.8 AA floor**, and a global `@media (pointer: coarse)` rule
(`app/assets/tailwind/application.css`) bumps every widget item to the full
44px on touch devices — the population target size protects. Everything
else — buttons, links, form controls, chips, tabs, breadcrumbs — is held to
44×44 with no exceptions. Do not widen this deviation without a design
review.

## Auditing Locally

The `AxeAccessibility` helpers are available in every system spec:

| Helper | Use |
|--------|-----|
| `axe_clean?` | true when the current page has zero violations |
| `axe_violations` | formatted violation messages; color-contrast failures include an ancestor-chain, theme, and animation debug payload |
| `axe_clean_in_both_themes?` | runs the audit in light and dark mode and ANDs the result |
| `axe_violations_in_both_themes` | combined light and dark violations, each prefixed with the active theme |

A typical check:

```ruby
it "is accessible in both themes" do
  visit dashboard_path

  expect(axe_clean_in_both_themes?).to be(true),
    axe_violations_in_both_themes.join("\n")
end
```

Because tokens are remapped under `.dark`, the both-themes helpers catch contrast regressions that surface in only one mode.

## Writing AAA-Compliant Code

The fastest way to pass the gate is to never hardcode color or size:

- **Use semantic tokens, not raw palette utilities.** `text-text-body`, `bg-surface`, and `border-border` resolve to AAA-verified values in both themes. Hardcoded utilities like `text-gray-400` or `bg-white` are not contrast-checked against the token system and drift over time. See [UI patterns](/docs/developer/ui-patterns) and [Components](/docs/developer/components).
- **Use the `focus-ring` utility for focus indicators** — an offset outline that stays visible in forced-colors mode and inside `overflow:hidden` ancestors, unlike `focus:ring-*` box-shadows.
- **Give interactive elements a 44×44px minimum target.** Pad small icon buttons rather than shrinking the hit area.
- **Let `.dark` do the theming.** Tokens remap automatically under the `.dark` selector, so markup rarely needs `dark:` variants.

For the token catalog and the live component states — each annotated with its accessibility contract — browse [`/lookbook`](/lookbook) in development.

## Deferred Debt and the Escape Hatch

A few surfaces carry known AAA-contrast debt that is tracked rather than allowed to block unrelated work. They live in one constant, `DEFERRED_AAA_EXCLUDES`, and are excluded from the default audit:

| Selector | Why it is deferred |
|----------|--------------------|
| `.highlight` | The Rouge syntax-highlighting palette sits at AA; raising it to AAA changes how every code sample looks sitewide |

This list is a visible, documented ledger — not a silent bypass. Two rules keep it honest:

1. Every entry names a concrete reason and is meant to shrink, never grow.
2. To audit an excluded surface deliberately, pass an explicit `exclude:` argument; use `exclude: []` for the raw, unfiltered audit.

### Resolved

- **`.biscuit-banner`** (resolved, #462) — the consent banner's contrast debt
  was fixed in the #500-era banner rework, but the exclusion outlived the
  debt: the first surface every signed-out visitor meets was exempt from
  *every* rule, not just contrast. An unexcluded audit passes both themes
  clean (`spec/system/accessibility/cookie_banner_axe_spec.rb`); the banner
  is now in scope for every default audit.
- **`.text-danger`** (resolved on `feat/ui-alert-exemplar`) — dark-mode danger text sat at 6.84:1 on `bg-surface-raised` (the lightest dark surface, neutral-800), below AAA's 7:1. Fixed at the token level by raising dark `--color-danger` / `--color-danger-icon` from `L=0.808` to `L=0.825` (now 7.08:1 measured on surface-raised, higher on the darker surfaces). The exclusion was retired and danger text is now held to AAA app-wide in both themes; `spec/system/ui/alert_component_spec.rb` proves it unscoped on the alert.

When you add UI, assume it must pass at AAA with no new exclusion. Reach for the ledger only for genuinely tracked debt — and write down why.

## What the Gate Does and Does Not Cover

An honest conformance claim names its scope. If you publish an accessibility
statement for a fork built on this template, base it on this, not on the
headline:

**Covered by the automated gate:** every rendered app route and component
preview exercised by the system suite, audited at AAA in **both themes**;
target sizes and focus indicators via the custom rules above; the consent
banner (#462); and **open-state keyboard contracts** for the widgets whose
operability is keyboard-defined — command palette, date picker, and
timepicker each have keyboard-driven specs that arrow through the live
widget and assert the ARIA state a screen reader consumes (the pattern to
copy when you add an interactive component: audit the OPEN state, not just
the closed default — the closed-state-only audits above hid four real
violations until #463).

**Outside the gate, tracked:** mailer templates (no previews exist yet;
issue #461 fires on the next mailer edit), the `.highlight` Rouge palette
(AA, deferred above), and any widget state a spec never drives. Real assistive
technology is not exercised at all — axe reads the DOM/ARIA that AT
consumes, which is strong evidence and still not the same as a screen-reader
session.

## The Manual Screen-Reader Pass

The gate ends where your obligation begins. This is the procedure for the part
no suite performs — run it before you publish an accessibility statement, and
again whenever a form, overlay or live region changes shape.

It is a procedure, not a tutorial. It assumes you can drive a screen reader and
tells you what *correct* sounds like on the four surfaces where this app's
narration is non-obvious.

### Setup

macOS with Safari. VoiceOver toggles with **Cmd+F5**; the rotor is **VO+U**
(navigate landmarks, headings and links); "read from here" is **VO+A**.

Record the OS, Safari and VoiceOver versions at the top of every result. A pass
without versions cannot be compared to the next one, which is the whole point of
recording it.

### The four surfaces

**A. A form that failed to submit.** Any form rendering `form.error_summary` —
registration with both name fields blank, or the onboarding workspace and
project steps with the name blank, are the three used previously.

The markup pairs two things deliberately: the focus target is a **role-less**
container carrying `tabindex="-1"` and `autofocus`, and its child carries
`role="alert"`. An assertive live region next to a focus move is exactly the
arrangement that produces a double announcement on some readers, so that is the
thing under test.

After submitting, touch nothing. Correct sounds like: the heading
("N errors prevented this from being saved") **once**; then the list — the `ul`
keeps `list-disc` so list semantics survive — with each item read as a link.
Tab lands on the first link. Enter moves to the field and announces its label,
that it is invalid, and its inline error.

It fails if there is silence, if the heading is announced **twice**, or if focus
lands on `<body>` or on a field rather than the summary.

*Baseline, observed 2026-09-08 (VoiceOver/Safari): behaved as expected — no
double announcement and no silence. NVDA/Firefox has never been run.*

**B. A toast or a flash.** The container (`shared/_toasts.html.erb`) is
`role="region"` with `aria-live="polite"` and an `aria-label`, present and empty
from first render.

A toast streamed in after load is spoken **once**, politely, and focus does not
move. A flash rendered *with* the page is a different case: it is already
inside the region at load rather than inserted into it. What a reader does
with that has **not been observed** — the expectation that used to sit here
was read off the accessibility tree, not from a real reader (#901), and the
2026-09-23 retrospective judged it wrong. #1267 owns the cold run: record what
actually happens, and the recording replaces this paragraph.

**C. A modal opening and closing.** A native `<dialog>` with `aria-modal="true"`
and `aria-labelledby` pointing at its title, opened via `showModal`.

Correct: the title then "dialog", then the first focusable control. VoiceOver
cannot reach content behind it. Escape closes it and focus returns to the
trigger. That return is native `showModal` behaviour rather than anything this
app implements — record it rather than assuming it.

**D. The command palette.** A combobox: the input keeps DOM focus with
`aria-expanded="true"`, options live in a sibling `role="listbox"`, and a
`role="status"` region reports the result count.

Correct: the input is announced as a combobox; each arrow key speaks the newly
highlighted option by name; Enter activates it; Escape closes and returns focus
to the trigger. **The exact phrasing here is unverified** — deriving it from the
DOM is guesswork, and producing it is what this run is for.

### Recording a result

Per surface: the trigger, then the transcript **in order and verbatim**, then
what was silent, then pass or fail against each lettered check above. Versions
at the top. One follow-up issue per failure, citing the letter. Paste the record
into the issue that asked for the pass — an unrecorded pass is a pass nobody can
check.

### The standing caveat

VoiceOver and NVDA disagree about live regions and about focus after a Turbo
render. **A VoiceOver-only pass is evidence, not proof**, and a close-out that
rests on one reader has to say which one.
