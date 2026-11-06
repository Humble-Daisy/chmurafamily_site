require "rails_helper"

# One pages resource, show keyed by name; the templates are the allowlist (#1007).
RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "returns the home page" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.home.hero.title"))
    end

    it "includes the footer" do
      get root_path
      expect(response.body).to include(I18n.t("footer.about"))
    end

    it "includes navigation" do
      get root_path
      expect(response.body).to include(I18n.t("application.name"))
    end
  end

  describe "sign-up CTA visibility" do
    context "when SIGNUP_MODE is :open" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

      it "shows the Sign up CTA button on the landing page" do
        get root_path
        # The bottom-CTA button ("Create your account") is only rendered when signups_open?.
        expect(response.body).to include(I18n.t("pages.home.cta.button"))
      end

      it "renders the secondary hero CTA as a brand-outline button" do
        get root_path
        expect(Capybara.string(response.body)).to have_css("a.btn-outline-primary",
          text: I18n.t("pages.home.hero.cta_secondary"))
      end
    end

    context "when SIGNUP_MODE is :invite_only without a token" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "does NOT show the Sign up CTA button on the landing page" do
        get root_path
        # The CTA button ("Create your account") is suppressed when signups are closed.
        expect(response.body).not_to include(I18n.t("pages.home.cta.button"))
      end

      it "still shows the Sign in CTA" do
        get root_path
        expect(response.body).to include(new_session_path)
      end
    end
  end

  describe "landing page for a signed-in user" do
    let(:user) { create(:user) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      sign_in(user)
    end

    it "swaps the hero CTA for a workspaces link" do
      get root_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("pages.home.hero.cta_signed_in"), href: workspaces_path
      )
    end

    it "softens the bottom CTA section and links to workspaces" do
      get root_path
      page = Capybara.string(response.body)
      expect(response.body).to include(I18n.t("pages.home.cta.signed_in.title"))
      expect(response.body).to include(I18n.t("pages.home.cta.signed_in.subtitle"))
      expect(page).to have_link(I18n.t("pages.home.cta.signed_in.button"), href: workspaces_path)
    end

    it "does not render the sign-up copy or a sign-in link CTA" do
      get root_path
      expect(response.body).not_to include(I18n.t("pages.home.cta.title"))
      expect(Capybara.string(response.body)).to have_no_link(
        I18n.t("pages.home.hero.cta_primary"), href: new_session_path
      )
    end

    it "shows the workspaces CTA even when signups are closed" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      get root_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("pages.home.cta.signed_in.button"), href: workspaces_path
      )
    end
  end

  describe "landing page for a user with no workspace" do
    it "renders without a 500" do
      sign_in(create(:user, :with_zero_workspaces))
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the about page as the public_page recipe's reference" do
    it "renders the partials the recipe names" do
      about = Rails.root.join("app/views/pages/about.html.erb").read
      expect(about).to include("shared/hero", "shared/section")
    end
  end

  describe "GET /about" do
    it "returns the about page with mission" do
      get page_path(:about)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.about.hero.title"))
    end
  end

  describe "GET /privacy" do
    it "returns the privacy page with policy sections" do
      get page_path(:privacy)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.privacy.title"))
    end

    # Guards the :long format on the "last updated" stamp — switching the
    # template to :short, or dropping the `l` call for a raw strftime, fails
    # here. It does NOT guard locale overrides: a fork redefining
    # date.formats.long moves the rendered output and an `I18n.l` expectation
    # together, so the literal is the only version that can fail.
    # Time is frozen because Date.current would otherwise be evaluated once in
    # the request and once in the assertion — different values across midnight.
    it "renders the updated-on date in the :long format" do
      travel_to Time.zone.local(2026, 7, 25, 12, 0, 0) do
        get page_path(:privacy)
        expect(response.body).to include("July 25, 2026")
      end
    end
  end

  describe "GET /contact" do
    it "returns the contact page with methods" do
      get page_path(:contact)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.contact.hero.title"))
    end
  end

  describe "GET /:id for a name that is not a page" do
    it "is not routable, so the constraint is the first fence" do
      get "/pricing"
      expect(response).to have_http_status(:not_found)
    end
  end
end
