require "rails_helper"

RSpec.describe "Footer: Cookie settings reopens Biscuit banner", type: :system do
  it "renders a Cookie settings button in the footer on public pages" do
    visit new_session_path
    within("footer") do
      expect(page).to have_button(I18n.t("footer.cookie_settings"))
    end
  end

  it "reopens the Biscuit banner when clicked" do
    visit new_session_path

    # Simulate a post-consent state: hide the banner and show the manage-link
    # (exactly what the Biscuit controller does after acceptAll/rejectAll).
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) { banner.hidden = true; banner.setAttribute("aria-hidden", "true"); }
      const link = document.querySelector('[data-biscuit-target="manageLink"]');
      if (link) link.hidden = false;
    JS

    # Sanity: banner should now be hidden
    expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden)

    within("footer") do
      click_button I18n.t("footer.cookie_settings")
    end

    # Biscuit's reopen action calls #showBanner, making the banner visible again.
    expect(page).to have_css("[data-biscuit-target='banner']:not([hidden])", wait: 2)
  end

  it "hides the gem's floating .biscuit-manage-link so only our footer button shows" do
    visit new_session_path
    # The gem still renders it in the DOM; our CSS hides it with display:none !important.
    expect(page).to have_css(".biscuit-manage-link", visible: :hidden)
    expect(page).not_to have_css(".biscuit-manage-link", visible: true)
  end

  it "syncs category checkboxes to the saved consent before reopening (no stale state)" do
    visit new_session_path

    # Accept all: updates the cookie via a fetch POST, but never touches the
    # (still-in-DOM, just-hidden) category checkboxes — they stay whatever
    # they rendered as at page load (unchecked, on a first visit). No fresh
    # server render happens here (it's an async fetch, not a navigation), so
    # this stays the FIRST-VISIT DOM structure — reopen() only re-shows the
    # outer banner; the checkboxes only become visible via the still-present
    # "Manage preferences" toggle, exactly as they would for a real user
    # who accepts, then reconsiders granular choices without reloading.
    click_button I18n.t("biscuit.banner.accept_all")
    expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden, wait: 2)

    within("footer") { click_button I18n.t("footer.cookie_settings") }
    expect(page).to have_css("[data-biscuit-target='banner']:not([hidden])", wait: 2)

    click_button I18n.t("biscuit.banner.manage")

    # Without the sync fix, these would still read unchecked (stale from
    # page load) even though the cookie now says every category is true.
    checkboxes = all("[data-biscuit-target='categoryCheckbox']", wait: 2)
    expect(checkboxes).not_to be_empty
    checkboxes.each { |checkbox| expect(checkbox).to be_checked }
  end

  it "does not offer Cancel on first visit (an explicit consent choice is required)" do
    visit new_session_path
    click_button I18n.t("biscuit.banner.manage") # open the preferences panel

    expect(page).to have_button(I18n.t("biscuit.banner.save"))
    expect(page).not_to have_button(I18n.t("cookie_consent.cancel"))
  end

  describe "manage-mode banner (reopened after a fresh page load with consent already given)" do
    before do
      visit new_session_path # establish the domain before setting a cookie on it
      page.driver.browser.cookies.set(
        name: "biscuit_consent",
        value: Biscuit::Consent.build_value(analytics: true, marketing: false, preferences: false).to_json,
        domain: URI.parse(page.current_url).host
      )
      visit new_session_path # fresh render: consent.given? is now true server-side
    end

    it "renders the banner hidden server-side (no flash), reopens on the footer click, and passes AAA" do
      expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden)

      within("footer") { click_button I18n.t("footer.cookie_settings") }
      expect(page).to have_css("[data-biscuit-target='banner']:not([hidden])", wait: 2)

      # No "Manage preferences" toggle to click this time — manage mode
      # renders the checkboxes directly (fresh server render, not carried
      # over from a stale first-visit DOM like the test above).
      expect(page).to have_css("input[data-category='analytics']:checked", wait: 2)
      expect(page).to have_css("input[data-category='marketing']", wait: 2)
      expect(page).not_to have_css("input[data-category='marketing']:checked")

      scope = [ "[data-biscuit-target='banner']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end

    it "offers Cancel: dismisses without changing consent, discards toggles, and closes on Escape" do
      within("footer") { click_button I18n.t("footer.cookie_settings") }
      expect(page).to have_css("[data-biscuit-target='banner']:not([hidden])", wait: 2)
      expect(page).to have_button(I18n.t("cookie_consent.cancel"))
      expect(page).to have_css("input[data-category='analytics']:checked", wait: 2)

      # Toggle analytics off (unsaved), then Cancel — the banner hides and no
      # consent POST fires.
      find("input[data-category='analytics']").click
      click_button I18n.t("cookie_consent.cancel")
      expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden, wait: 2)

      # Consent unchanged: reopen and analytics is still checked — the toggle
      # was discarded, not saved.
      within("footer") { click_button I18n.t("footer.cookie_settings") }
      expect(page).to have_css("input[data-category='analytics']:checked", wait: 2)

      # Escape dismisses the reopened panel too.
      find("body").send_keys(:escape)
      expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden, wait: 2)
    end
  end
end
