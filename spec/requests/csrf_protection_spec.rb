require "rails_helper"

# The test environment turns forgery protection off, so this file is the one place it runs.
RSpec.describe "CSRF protection by Sec-Fetch-Site", type: :request do
  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  let!(:user) { create(:user) }

  it "accepts a same-origin POST that carries no authenticity token" do
    post session_lookup_path, params: { email_address: user.email_address },
      headers: { "Sec-Fetch-Site" => "same-origin" }

    expect(response).to have_http_status(:ok)
  end

  it "rejects a cross-site POST" do
    post session_lookup_path, params: { email_address: user.email_address },
      headers: { "Sec-Fetch-Site" => "cross-site" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a POST with no Sec-Fetch-Site header over HTTPS" do
    https!
    post session_lookup_path, params: { email_address: user.email_address }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a POST with no Sec-Fetch-Site header over HTTPS even when it carries a valid token" do
    https!
    get new_session_path
    token = Capybara.string(response.body).find("[data-biscuit-csrf-token-value]", visible: :all)["data-biscuit-csrf-token-value"]
    expect(token).to be_present
    post session_lookup_path, params: { email_address: user.email_address, authenticity_token: token }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders no csrf-token meta tag, since no request is checked against one" do
    get new_session_path

    expect(response.body).not_to include('name="csrf-token"')
  end

  it "accepts a same-origin JSON POST to a passkey endpoint that carries no token, as webauthn_controller sends it" do
    post passkeys_authentication_challenge_path, as: :json, headers: { "Sec-Fetch-Site" => "same-origin" }

    expect(response).to have_http_status(:ok)
  end

  it "rejects a cross-site JSON POST to a passkey endpoint" do
    post passkeys_authentication_challenge_path, as: :json, headers: { "Sec-Fetch-Site" => "cross-site" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lets the OmniAuth request phase through from the same origin" do
    post "/auth/google_oauth2", headers: { "Sec-Fetch-Site" => "same-origin" }

    expect(response).to redirect_to("/auth/google_oauth2/callback")
  end
end
