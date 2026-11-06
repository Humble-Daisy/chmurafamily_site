require "rails_helper"

RSpec.describe "Security headers" do
  it "includes Referrer-Policy" do
    get new_session_path
    expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "does not send X-XSS-Protection, which every browser has dropped" do
    get new_session_path
    expect(response.headers).not_to have_key("X-XSS-Protection")
  end

  it "denies the camera, microphone and location through Permissions-Policy" do
    get new_session_path
    expect(response.headers["Permissions-Policy"]).to eq("camera=(), microphone=(), geolocation=()")
  end
end
