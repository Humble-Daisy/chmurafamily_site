require "rails_helper"

RSpec.describe "Static pages", type: :system do
  describe "home page" do
    before { visit root_path }

    it "displays the hero title" do
      expect(page).to have_text(I18n.t("pages.home.hero.title"))
    end

    it "displays the hero subtitle" do
      expect(page).to have_text(I18n.t("pages.home.hero.subtitle"))
    end

    it "has call-to-action buttons when signups are open" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      visit root_path
      expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"))
      expect(page).to have_link(I18n.t("pages.home.hero.cta_secondary"))
    end

    it "displays feature cards" do
      expect(page).to have_text(I18n.t("pages.home.features.auth.title"))
      expect(page).to have_text(I18n.t("pages.home.features.workspaces.title"))
      expect(page).to have_text(I18n.t("pages.home.features.projects.title"))
    end
  end

  describe "about page" do
    before { visit page_path(:about) }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.about.hero.title"))
    end

    it "displays the mission" do
      expect(page).to have_text(I18n.t("pages.about.mission.title"))
    end

    it "lists key features" do
      expect(page).to have_text(I18n.t("pages.about.features.title"))
    end
  end

  describe "privacy page" do
    before { visit page_path(:privacy) }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.privacy.title"))
    end

    it "has policy sections" do
      expect(page).to have_text(I18n.t("pages.privacy.collection.title"))
      expect(page).to have_text(I18n.t("pages.privacy.usage.title"))
      expect(page).to have_text(I18n.t("pages.privacy.security.title"))
    end
  end

  describe "contact page" do
    before { visit page_path(:contact) }

    it "heads the page with the hero title" do
      expect(page).to have_css("h1", exact_text: I18n.t("pages.contact.hero.title"))
    end

    it "displays contact methods" do
      expect(page).to have_text(I18n.t("pages.contact.methods.title"))
    end
  end

  describe "post-navigation focus" do
    it "moves focus to #main-content after a Turbo Drive navigation" do
      visit new_session_path
      click_link I18n.t("footer.about") # destination has no autofocused field

      expect(page).to have_css("#main-content:focus")
    end
  end

  describe "accessibility (axe-core)" do
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    %w[home about privacy contact].each do |page_name|
      it "#{page_name} page passes automated accessibility checks (light + dark)" do
        path = page_name == "home" ? root_path : page_path(page_name)
        visit path
        expect(axe_clean_in_both_themes?(axe_options)).to be(true),
          "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
      end
    end
  end
end
