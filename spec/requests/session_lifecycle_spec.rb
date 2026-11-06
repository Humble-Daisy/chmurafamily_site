require "rails_helper"

RSpec.describe "Session lifecycle", type: :request do
  let(:user) { create(:user, password: "SecureP@ssw0rd123!") }

  def sign_in_and_get_session
    sign_in(user)
    get workspaces_path
    user.sessions.order(:created_at).last
  end

  it "resumes an active session" do
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "refuses an expired session and redirects to sign in with an announced reason" do
    session = sign_in_and_get_session
    session.update_columns(last_active_at: (Session.idle_timeout + 1.day).ago)

    get edit_settings_profile_path
    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(flash[:alert]).to eq(I18n.t("authentication.session_expired"))
  end

  it "refuses a session whose row was revoked (swept), with the same reason" do
    session = sign_in_and_get_session
    session.destroy!

    get edit_settings_profile_path
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("authentication.session_expired"))
  end

  it "gives an unauthenticated visitor no session-expired flash" do
    get edit_settings_profile_path
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to be_blank
  end

  it "stores a path-only return_to (no host)" do
    get edit_settings_profile_path
    expect(session[:return_to_after_authenticating]).to eq(edit_settings_profile_path)
  end

  it "refreshes last_active_at on activity (throttled)" do
    session = sign_in_and_get_session
    session.update_columns(last_active_at: (Session.touch_throttle + 1.minute).ago)
    before = session.reload.last_active_at

    get workspaces_path
    expect(session.reload.last_active_at).to be > before
  end
end
