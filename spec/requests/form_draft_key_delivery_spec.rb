require "rails_helper"

RSpec.describe "Form draft key delivery" do
  let(:user) { create(:user) }

  context "signed in" do
    before { sign_in(user) }

    it "delivers both form-draft meta tags with correct values" do
      get workspace_path(user.personal_workspace)
      doc = Capybara.string(response.body)
      key_meta   = doc.find('meta[name="form-draft-key"]', visible: :all)
      scope_meta = doc.find('meta[name="form-draft-scope"]', visible: :all)
      expect(Base64.strict_decode64(key_meta[:content])).to eq(FormDraftKey.for(user))
      expect(scope_meta[:content]).to eq(FormDraftKey.scope_for(user))
    end

    it "sends Cache-Control: no-store on authenticated HTML" do
      get workspace_path(user.personal_workspace)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  context "signed out" do
    it "renders no form-draft meta tags" do
      get new_session_path
      doc = Capybara.string(response.body)
      expect(doc).to have_no_css('meta[name="form-draft-key"]', visible: :all)
      expect(doc).to have_no_css('meta[name="form-draft-scope"]', visible: :all)
    end
  end
end
