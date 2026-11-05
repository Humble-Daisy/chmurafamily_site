require "rails_helper"

RSpec.describe "Email verification banner", type: :request do
  it "shows the banner to a signed-in user with an unverified email" do
    user = create(:user, :unverified_email)
    sign_in(user)
    get workspaces_path
    expect(response.body).to include("verify-banner")
  end

  # #731: the banner is a labelled region (UI::Banner) — present on load, not
  # a live region; the old role=status re-announced on every Turbo render.
  it "renders as a labelled region, not a live region" do
    user = create(:user, :unverified_email)
    sign_in(user)
    get workspaces_path
    banner = Capybara.string(response.body).find("#verify-banner")
    expect(banner["role"]).to eq("region")
    expect(banner["aria-label"]).to be_present
  end

  it "hides the banner once the email is verified" do
    user = create(:user, :unverified_email)
    user.authentications.email.first.update!(verified_at: Time.current)
    sign_in(user)
    get workspaces_path
    expect(response.body).not_to include("verify-banner")
  end
end
