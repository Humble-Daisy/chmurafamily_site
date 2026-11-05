# frozen_string_literal: true

require "rails_helper"

# Harness self-test: proves the axe gate's default option set selects the full
# cumulative WCAG A/AA/AAA rule stack. axe's `runOnly` tags are NOT
# cumulative — passing only "wcag2aaa" selects just the 3 AAA-tagged rules and
# silently skips the whole A/AA foundation (labels, alt text, names, titles).
# Exactly that regression shipped once (fixed in the #540–#542 arc); this spec
# exists so it can never happen silently again.
#
# It injects a deliberately broken element instead of visiting a real broken
# page — the subject under test is the audit harness itself, not app UI, so
# the project rule "system specs test real rendered HTML" does not apply.
RSpec.describe "axe gate rule coverage", type: :system do
  it "selects the full A/AA/AAA rule stack, not just AAA-tagged rules" do
    visit new_session_path
    inject_axe

    rule_ids = page.evaluate_script(
      "axe.getRules(#{AxeAccessibility::AXE_TAG_SET.to_json}).map(r => r.ruleId)"
    )

    expect(rule_ids).to include(
      "label", "image-alt", "link-name", "button-name", "document-title",
      "html-has-lang", "target-size", "color-contrast-enhanced"
    )
    expect(rule_ids.length).to be > 40
  end

  # The gap that let the regression back in (#829). The two examples around
  # this one cover the CONSTANT and the DEFAULT path — neither covers the
  # path 32 system specs actually take, which is passing their own runOnly.
  # `options[:runOnly] ||= DEFAULT` meant a caller-supplied value REPLACED
  # the cumulative set rather than adding to it, so those specs audited the
  # three AAA-tagged rules and skipped the whole A/AA foundation, with this
  # very spec green the entire time. A guard that tests the default while the
  # callers bypass the default is not a guard.
  it "cannot be narrowed below the cumulative stack by a caller-supplied runOnly" do
    visit new_session_path
    page.execute_script(<<~JS)
      document.body.insertAdjacentHTML(
        "beforeend", '<input id="a11y-narrowing-probe" type="text">'
      )
    JS

    # "label" is wcag2a — absent from a literal ["wcag2aaa"] rule selection.
    results = run_axe_audit(
      { runOnly: { type: "tag", values: [ "wcag2aaa" ] } },
      exclude: [], include: "#a11y-narrowing-probe"
    )

    expect(results["violations"].map { |v| v["id"] }).to include("label")
  ensure
    page.execute_script('document.getElementById("a11y-narrowing-probe")?.remove()')
  end

  it "catches a seeded unlabeled input under the gate's default options" do
    visit new_session_path
    page.execute_script(<<~JS)
      document.body.insertAdjacentHTML(
        "beforeend", '<input id="a11y-gate-probe" type="text">'
      )
    JS

    results = run_axe_audit(exclude: [], include: "#a11y-gate-probe")

    expect(results["violations"].map { |v| v["id"] }).to include("label")
  ensure
    # The CI after-hook re-audits the page (both themes), so the deliberately
    # broken probe must not leak into it.
    page.execute_script('document.getElementById("a11y-gate-probe")?.remove()')
  end

  # The open cookie banner is a role="dialog", so axe defers this rule instead of failing it (#1549).
  it "fails a focusable aria-hidden control even when axe defers the rule for an open dialog" do
    visit new_session_path
    expect(page).to have_css(".biscuit-banner")
    page.execute_script(<<~JS)
      document.querySelector("main").insertAdjacentHTML(
        "beforeend", '<button id="a11y-hidden-focus-probe" aria-hidden="true">Probe</button>'
      )
    JS

    results = run_axe_audit(exclude: [], include: "#a11y-hidden-focus-probe")

    expect(results["violations"].map { |v| v["id"] }).to include("aria-hidden-focus")
  ensure
    page.execute_script('document.getElementById("a11y-hidden-focus-probe")?.remove()')
  end
end
