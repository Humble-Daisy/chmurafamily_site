require "rails_helper"

RSpec.describe "Notifications a11y plumbing", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  describe "aria-live region" do
    it "renders an empty polite-atomic live region for announcement updates" do
      sign_in_via_form(user)
      visit new_session_path

      # `visible: :all` because `.sr-only` clips the element off-screen for
      # sighted users; assistive tech still reads it.
      live = find("#notifications-live", visible: :all)
      expect(live["aria-live"]).to eq("polite")
      expect(live["aria-atomic"]).to eq("true")
      expect(live.text).to eq("")
    end
  end

  describe "indicator-frame turbo-stream subscription (v2)" do
    it "renders a turbo-stream-from subscription + the v2 indicator frames for authenticated users" do
      sign_in_via_form(user)
      visit new_session_path

      expect(page).to have_css("turbo-cable-stream-source", visible: :all)
      # v2 frames (supersedes D1's notifications_bell_label_frame +
      # notifications_bell_indicator_frame):
      #   notifications_indicator_avatar    — severity dot on avatar
      #   notifications_indicator_hamburger — severity dot on hamburger
      #   notifications_menu_count_frame    — [N new] badge in the user menu
      # Each lives OUTSIDE the focusable button's accessible-name path so AT
      # users get notification state via the user-menu aria-live region rather
      # than via a swapping aria-label mid-click (D1's lesson preserved).
      expect(page).to have_css("turbo-frame#notifications_indicator_avatar", visible: :all)
      expect(page).to have_css("turbo-frame#notifications_indicator_hamburger", visible: :all)
      expect(page).to have_css("turbo-frame#notifications_menu_count_frame", visible: :all)
    end

    it "does NOT render the subscription on unauthenticated pages" do
      visit new_session_path

      expect(page).to have_button(I18n.t("sessions.new.continue"))
      expect(page).to have_no_css("turbo-cable-stream-source")
    end
  end
end
