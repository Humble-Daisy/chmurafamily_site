# frozen_string_literal: true

require "rails_helper"

# Some screen readers name a field from its first label only, so a second label risks an empty or wrong name.
RSpec.describe "Timezone select labelling", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  {
    "appearance settings" => [ -> { edit_settings_theme_preference_path }, "settings.appearance.timezone.label" ],
    "notification preferences" => [ -> { edit_settings_notification_preferences_path }, "notifications.preferences.timezone.picker_label" ]
  }.each do |page_name, (path, label_key)|
    it "gives the timezone select on #{page_name} exactly one label, in the page's words" do
      get instance_exec(&path)
      doc = Nokogiri::HTML(response.body)
      select = doc.at_css("select[name='timezone']")

      expect(select).not_to be_nil
      labels = doc.css("label[for='#{select['id']}']")
      expect(labels.map { |label| label.text.squish }).to eq([ I18n.t(label_key) ])
    end
  end
end
