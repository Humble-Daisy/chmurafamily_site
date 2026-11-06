# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey enrollment prompt", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "shows the enrollment banner on an authenticated page, then never again once dismissed" do
    # The factory default stamps passkey_prompt_seen_at to suppress the banner;
    # reset to nil to make this user eligible.
    user.update!(passkey_prompt_seen_at: nil)
    get workspaces_path
    expect(response.body).to include('id="passkey-banner"')
    # Discriminator: `info-border` (a phantom — no compiled selector) shipped here
    # until Panel CP3; the real utility is border-info-border.
    expect(Capybara.string(response.body)).to have_css("#passkey-banner.border-info-border")
    patch passkey_prompt_path # dismiss (×) — stamps passkey_prompt_seen_at
    get workspaces_path
    expect(response.body).not_to include('id="passkey-banner"')
  end

  it "does not show once the user already has a passkey (independent of seen_at)" do
    user.update!(passkey_prompt_seen_at: nil)
    create(:webauthn_credential, user: user)
    get workspaces_path
    expect(response.body).not_to include('id="passkey-banner"')
  end
end
