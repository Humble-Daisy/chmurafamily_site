require "rails_helper"
require "turbo/broadcastable/test_helper"

# Regression: NotificationBroadcaster refreshed the avatar dot, hamburger dot,
# and user-menu count by `broadcast_replace_to`-ing each <turbo-frame> id with a
# CONTENT-ONLY partial (the partial renders the frame's children, never the frame
# itself). Turbo's `replace` swaps the whole target element, so repeat broadcasts
# could no longer re-target the frame and the surfaces froze after the first
# refresh — the count would show "1 new" forever even as more arrived. The fix is
# `broadcast_update_to` (swap the frame's inner content, keep the frame element).
#
# This spec replays the REAL captured broadcast through the REAL Turbo client
# (window.Turbo.renderStreamMessage) rather than the cable — the test cable
# adapter only records broadcasts, it does not deliver them to the browser — so
# the assertion exercises actual Turbo stream semantics. The bug only manifests
# across TWO consecutive broadcasts, so the test delivers twice and asserts the
# second refresh lands. Capybara's `have_text` auto-waits for Turbo's async
# stream application.
RSpec.describe "Notification broadcast frame persistence", type: :system do
  include Turbo::Broadcastable::TestHelper

  let(:user) { create(:user) }

  # Monotonic offset so each delivery lands in a distinct idempotency bucket
  # (same pattern as notifications_index_spec — see project memory
  # `project_flaky_tests_followup.md`).
  def deliver_security_notification(recipient = user)
    @offset ||= 0
    @offset += 5
    travel_to(Time.current + @offset.minutes) do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
    end
  end

  # Capture the broadcaster's real turbo-stream output and apply it to the live
  # page exactly as Action Cable would. We read the recorded broadcasts directly
  # (ActionCable TestHelper) rather than `capture_turbo_stream_broadcasts`'s block
  # form, which depends on Minitest assertions unavailable under RSpec.
  def broadcast_refresh_and_apply
    stream = stream_name_from([ user, :notifications ])
    clear_messages(stream)
    NotificationBroadcaster.refresh_for(
      user, announcement_key: "notifications.bell.arrival_announcement"
    )
    html = broadcasts(stream).map { |payload| ActiveSupport::JSON.decode(payload) }.join
    page.execute_script("window.Turbo.renderStreamMessage(arguments[0])", html)
  end

  before { sign_in_via_form(user) }

  it "keeps refreshing the user-menu count across consecutive broadcasts" do
    user.notifications.destroy_all
    visit new_session_path
    find("#user-menu-button").click

    deliver_security_notification
    broadcast_refresh_and_apply
    within "#user-menu" do
      expect(page).to have_text(I18n.t("navigation.notifications_count", count: 1))
    end

    deliver_security_notification
    broadcast_refresh_and_apply
    # The second broadcast must land — with the `replace` bug the count froze at
    # "1 new" because the frame element was no longer addressable.
    within "#user-menu" do
      expect(page).to have_text(I18n.t("navigation.notifications_count", count: 2))
    end

    # And the frame itself stays in the DOM, addressable for the next refresh.
    expect(page).to have_css("turbo-frame#notifications_menu_count_frame", visible: :all)
  end
end
