require "rails_helper"

RSpec.describe "Avatar notification indicator v2", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  # Helper: deliver a notification of a known severity by class
  def deliver_danger;  PasswordChangedNotifier.with(record: user).deliver(user); end
  def deliver_info
    invitation = create(:invitation, email: user.email_address)
    WorkspaceInvitationResentNotifier.with(record: invitation).deliver(user)
  end
  def deliver_warning
    workspace = create(:workspace)
    role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end
    create(:membership, user: user, workspace: workspace, role: role)
    WorkspaceCapacityApproachingNotifier
      .with(record: workspace, metric: :members, current: 8, limit: 10)
      .deliver(user)
  end

  before { sign_in_via_form(user) }

  describe "severity colors render correctly at each level" do
    it "renders a danger-colored pulsing dot for danger-severity unread" do
      deliver_danger
      visit new_session_path
      dot = page.find('turbo-frame#notifications_indicator_avatar [data-severity]', visible: :all)
      expect(dot["data-severity"]).to eq("danger")
      expect(dot[:class]).to match(/bg-danger-strong/)
      expect(dot[:class]).to match(/motion-safe:animate-pulse/)
    end

    it "renders a warning-colored static dot for warning-severity unread" do
      # Wipe sign-in notifier first so warning is the highest severity present.
      user.notifications.destroy_all
      deliver_warning
      visit new_session_path
      dot = page.find('turbo-frame#notifications_indicator_avatar [data-severity]', visible: :all)
      expect(dot["data-severity"]).to eq("warning")
      expect(dot[:class]).to match(/bg-warning(\s|"|$)/)
      expect(dot[:class]).not_to match(/animate-pulse/)
    end

    it "renders an info-colored static dot for info-severity unread" do
      user.notifications.destroy_all
      deliver_info
      visit new_session_path
      dot = page.find('turbo-frame#notifications_indicator_avatar [data-severity]', visible: :all)
      expect(dot["data-severity"]).to eq("info")
      expect(dot[:class]).to match(/bg-info(\s|"|$)/)
      expect(dot[:class]).not_to match(/animate-pulse/)
    end
  end

  describe "WCAG 2.2 AAA accessibility — both themes" do
    before do
      deliver_danger # ensure danger-severity dot is rendered for the audit
      visit new_session_path
    end

    it "passes axe-core at AAA in light mode with the indicator rendered" do
      ensure_light_mode
      expect(axe_clean?(axe_options)).to be(true),
        "Light-mode AAA violations:\n#{axe_violations(axe_options).join("\n")}"
    end

    it "passes axe-core at AAA in dark mode with the indicator rendered" do
      ensure_dark_mode
      expect(axe_clean?(axe_options)).to be(true),
        "Dark-mode AAA violations:\n#{axe_violations(axe_options).join("\n")}"
    end
  end

  describe "regression guards (D1 partials must stay removed)" do
    it "does not render the standalone notifications bell link" do
      deliver_danger
      visit new_session_path
      expect(page).to have_css("turbo-frame#notifications_indicator_avatar", visible: :all)
      expect(page).to have_no_css("#notifications-bell-link")
      expect(page).to have_no_css('turbo-frame#notifications_bell_label_frame')
      expect(page).to have_no_css('turbo-frame#notifications_bell_indicator_frame')
    end
  end
end
