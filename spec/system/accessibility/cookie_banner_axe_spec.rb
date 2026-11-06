# frozen_string_literal: true

require "rails_helper"

# #462: the consent banner is the FIRST interactive surface every signed-out
# visitor meets, and it sat in DEFERRED_AAA_EXCLUDES from the day the axe
# harness landed — exempt from every rule (names, roles, focus, contrast),
# not just the contrast concern that motivated the deferral. This is the
# explicit, unexcluded audit: the banner subtree held to the same AAA bar as
# the rest of the UI, in both themes, plus the keyboard contract axe cannot
# see.
RSpec.describe "Cookie consent banner accessibility", type: :system do
  it "passes AAA in both themes with no exclusions" do
    visit new_session_path
    expect(page).to have_css(".biscuit-banner")

    expect(axe_clean_in_both_themes?(exclude: [])).to(
      be(true),
      axe_violations_in_both_themes(exclude: []).join("\n")
    )
  end

  it "exposes the preferences panel as a group named for what it manages" do
    visit new_session_path
    click_button I18n.t("biscuit.banner.manage")
    expect(page).to have_css("#biscuit-preferences-panel", visible: true)

    expect(ax_role("#biscuit-preferences-panel")).to eq("group")
    expect(ax_name("#biscuit-preferences-panel")).to eq(I18n.t("biscuit.banner.manage"))
  end

  it "is keyboard-operable: reject and accept are reachable, labeled buttons" do
    visit new_session_path

    within(".biscuit-banner") do
      reject = find_button(I18n.t("cookie_consent.reject_non_essential"))
      accept = find_button(I18n.t("biscuit.banner.accept_all"))

      reject.execute_script("this.focus()")
      expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq(reject.text)
      accept.execute_script("this.focus()")
      expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq(accept.text)
    end
  end
end
