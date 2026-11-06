require "rails_helper"

# A signed-in user may now legitimately have NO workspace (:none onboarding),
# so Current.workspace is nil on every authenticated page. This spec walks such
# a user through the pages a :none fork can reach and asserts each renders
# (200), never 500. It is the regression guard for "zero-workspace crash
# safety" (organizer-onboarding design, Template BLOCKERS).
RSpec.describe "Authenticated pages under :none onboarding (zero-workspace safety)", type: :request do
  let(:user) { create(:user, :with_zero_workspaces) }

  before { sign_in(user) }

  it "the user truly has no workspace" do
    expect(user.workspaces).to be_empty
    expect(user.personal_workspace).to be_nil
  end

  describe "GET /workspaces (index)" do
    it "renders without a 500" do
      get workspaces_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /workspaces/new" do
    it "renders without a 500" do
      get new_workspace_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/profile/edit (settings layout, Current.workspace nil)" do
    it "renders without a 500" do
      get edit_settings_profile_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/notification_preferences/edit (settings layout)" do
    it "renders without a 500" do
      get edit_settings_notification_preferences_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /account/connected_accounts (settings layout)" do
    it "renders without a 500" do
      get settings_connected_accounts_path
      expect(response).to have_http_status(:ok)
    end
  end
end
