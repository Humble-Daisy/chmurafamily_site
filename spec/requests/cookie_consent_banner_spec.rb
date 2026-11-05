require "rails_helper"

RSpec.describe "Cookie consent banner", type: :request do
  describe "first visit (no consent given)" do
    it "emphasizes Reject non-essential as primary and Accept all as secondary" do
      get new_session_path

      doc = Nokogiri::HTML(response.body)
      reject_button = doc.at_css("button[data-action='click->biscuit#rejectAll']")
      accept_button = doc.at_css("button[data-action='click->biscuit#acceptAll']")

      expect(reject_button).to be_present
      expect(accept_button).to be_present
      expect(reject_button.text).to include(I18n.t("cookie_consent.reject_non_essential"))
      expect(accept_button.text).to include(I18n.t("biscuit.banner.accept_all"))

      # Reject is the emphasized primary; Accept is the quiet secondary —
      # rejecting must be at least as easy as accepting (GDPR/ePrivacy), and
      # emphasizing Accept is a documented dark pattern.
      expect(reject_button["class"]).to include("biscuit-btn--primary")
      expect(accept_button["class"]).to include("biscuit-btn--secondary")
    end

    it "leaves non-essential category checkboxes unchecked (affirmative consent)" do
      get new_session_path

      checkboxes = Nokogiri::HTML(response.body).css("input[data-biscuit-target='categoryCheckbox']")
      expect(checkboxes).not_to be_empty
      checkboxes.each { |checkbox| expect(checkbox["checked"]).to be_nil }
    end

    it "still offers the manage-preferences toggle for granular consent" do
      get new_session_path
      toggle_button = Nokogiri::HTML(response.body).at_css("button[data-action='click->biscuit#togglePreferences']")
      expect(toggle_button).to be_present
    end
  end

  describe "manage mode (reopened after consent was already given)" do
    before do
      cookies[Biscuit.configuration.cookie_name] =
        Biscuit::Consent.build_value(analytics: true, marketing: false, preferences: true).to_json
    end

    it "drops the accept/reject/manage shortcuts, showing only checkboxes + Save" do
      get new_session_path
      doc = Nokogiri::HTML(response.body)

      expect(doc.at_css("button[data-action='click->biscuit#acceptAll']")).to be_nil
      expect(doc.at_css("button[data-action='click->biscuit#rejectAll']")).to be_nil
      expect(doc.at_css("button[data-action='click->biscuit#togglePreferences']")).to be_nil
      expect(doc.at_css("button[data-action='click->biscuit#savePreferences']")).to be_present
      expect(response.body).to include(I18n.t("cookie_consent.manage_message"))
    end

    it "pre-fills the category checkboxes from the saved consent" do
      get new_session_path
      doc = Nokogiri::HTML(response.body)

      expect(doc.at_css("input[data-category='analytics']")["checked"]).to eq("checked")
      expect(doc.at_css("input[data-category='marketing']")["checked"]).to be_nil
      expect(doc.at_css("input[data-category='preferences']")["checked"]).to eq("checked")
    end

    it "server-renders the banner hidden via the hidden attribute (no flash), not CSS" do
      get new_session_path
      banner = Nokogiri::HTML(response.body).at_css("[data-biscuit-target='banner']")
      expect(banner["hidden"]).to eq("hidden")
    end
  end
end
