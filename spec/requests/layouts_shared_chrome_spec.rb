require "rails_helper"

# Guards the layout chrome shared between application.html.erb and
# settings.html.erb via shared/_layout_head and shared/_layout_tail (#146):
# both layouts render the same head, skip link, and tail.
#
# Turbo morph (#327) is enabled wherever same-URL saves need to preserve
# scroll: unconditionally on the settings layout, and workspace-gated on the
# application layout (Current.workspace). Both provide the turbo-refresh-method
# meta through the shared head's yield :head hook; a plain application page
# with no active workspace does not.
RSpec.describe "Shared layout chrome", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  shared_examples "shared layout chrome" do
    it "renders the shared head, skip link, and notifications live region" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="description"]')).not_to be_nil
      expect(doc.at_css('link[rel="manifest"]')).not_to be_nil
      expect(doc.at_css('a[href="#main-content"]')).not_to be_nil
      expect(doc.at_css('#notifications-live[aria-live="polite"]')).not_to be_nil
    end

    it "subscribes to the stream NotificationBroadcaster sends the user's refreshes to" do
      streams = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to) { |stream, **| streams << stream }
      NotificationBroadcaster.refresh_for(user, announcement_key: "notifications.bell.read_state_announcement")
      broadcast_names = streams.uniq.map { |stream| Turbo::StreamsChannel.signed_stream_name(stream) }

      subscribed = Nokogiri::HTML(response.body).css("turbo-cable-stream-source").map { |el| el["signed-stream-name"] }
      expect(broadcast_names).not_to be_empty
      expect(subscribed).to include(*broadcast_names)
    end
  end

  context "application layout, no active workspace (workspaces index)" do
    before { get workspaces_path }

    include_examples "shared layout chrome"

    it "does not enable Turbo morph (no refresh-method meta)" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="turbo-refresh-method"]')).to be_nil
    end
  end

  context "application layout, active workspace page" do
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { get workspace_path(workspace) }

    it "enables Turbo morph so same-URL saves preserve scroll" do
      doc = Nokogiri::HTML(response.body)
      meta = doc.at_css('meta[name="turbo-refresh-method"]')
      expect(meta).not_to be_nil
      expect(meta["content"]).to eq("morph")
    end
  end

  context "settings layout" do
    before { get edit_settings_theme_preference_path }

    include_examples "shared layout chrome"

    it "enables Turbo morph for the settings hub (#327)" do
      doc = Nokogiri::HTML(response.body)
      meta = doc.at_css('meta[name="turbo-refresh-method"]')
      expect(meta).not_to be_nil
      expect(meta["content"]).to eq("morph")
    end
  end
end
