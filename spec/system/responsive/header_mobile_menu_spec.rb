# frozen_string_literal: true

require "rails_helper"

# Path Z: the shared header's mobile-menu panel auto-dismisses when an
# anchor inside the expanded panel is clicked. The Stimulus action and
# the data-action wiring on the menu element ship together as part of
# the header-accordion pattern. The accordion specs
# (spec/system/settings/mobile_accordion_spec.rb and
# spec/system/workspaces/mobile_accordion_spec.rb) exercise the wired
# end-to-end behavior under the real accordion content; this spec
# documents the auto-close intent on the bare header alone.
RSpec.describe "Shared header — mobile menu auto-close", type: :system, js: true do
  let(:user) { create(:user) }

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "wires closeOnLinkClick on the menu panel and dismisses on link tap" do
    visit root_path

    # The menu element should declare the auto-close action so any anchor
    # inside it dismisses the panel via event bubbling — no per-link wiring.
    expect(page).to have_css(
      "[data-mobile-menu-target='menu'][data-action*='mobile-menu#closeOnLinkClick']",
      visible: :all
    )

    # Open the panel, then dispatch a click on an anchor inside it.
    find("[data-mobile-menu-target='button']").click
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")

    page.execute_script(<<~JS)
      const link = document.querySelector("[data-mobile-menu-target='menu'] a")
      link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    JS

    # The closeOnLinkClick handler runs synchronously on bubble; before any
    # Turbo navigation completes, the menu should already carry the bare
    # `hidden` class. Use classList.contains rather than a string-include
    # check because the panel's permanent `md:hidden` modifier would false-
    # positive an include("hidden") substring match.
    has_hidden_class = page.evaluate_script(
      "document.querySelector(\"[data-mobile-menu-target='menu']\").classList.contains('hidden')"
    )
    expect(has_hidden_class).to be(true)
  end

  it "closes on Escape and hands focus back to the menu button" do
    visit root_path
    find("[data-mobile-menu-target='button']").click
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")

    cdp_press("Escape")

    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden", visible: :all)
    expect(page).to have_css("[data-mobile-menu-target='button'][aria-expanded='false']:focus")
  end

  it "closes the panel when the user clicks anywhere outside the header" do
    visit root_path

    # The header element declares a window-level click handler so taps
    # outside the header dismiss the panel — the classic click-outside-
    # to-close pattern. Wired at the controller's root element so the
    # handler can use `this.element.contains(event.target)` to
    # distinguish inside-vs-outside.
    expect(page).to have_css(
      "header[data-controller='mobile-menu'][data-action*='click@window->mobile-menu#closeOnOutsideClick']"
    )

    # Open the panel.
    find("[data-mobile-menu-target='button']").click
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")

    # Dispatch a click on the page's main content area (outside the header).
    # We send a bubbling MouseEvent so the window-level listener catches it.
    page.execute_script(<<~JS)
      const target = document.querySelector("main") || document.body
      target.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    JS

    has_hidden_class = page.evaluate_script(
      "document.querySelector(\"[data-mobile-menu-target='menu']\").classList.contains('hidden')"
    )
    expect(has_hidden_class).to be(true)
  end

  it "does NOT close when the click is INSIDE the header (e.g., user adjusting theme)" do
    visit root_path

    find("[data-mobile-menu-target='button']").click
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")

    # Click on the header itself (between elements) — should NOT close.
    # Picking the <header> tag directly (not a focusable child) so we test
    # the inside-the-controller-element discrimination, not link-click logic.
    page.execute_script(<<~JS)
      const header = document.querySelector("header[data-controller='mobile-menu']")
      header.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    JS

    # Check classList rather than substring-include — the panel's permanent
    # `md:hidden` class would false-positive an include("hidden") check.
    has_hidden_class = page.evaluate_script(
      "document.querySelector(\"[data-mobile-menu-target='menu']\").classList.contains('hidden')"
    )
    expect(has_hidden_class).to be(false), "panel should still be open after clicking inside the header"
  end
end
