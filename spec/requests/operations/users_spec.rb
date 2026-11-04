require "rails_helper"

RSpec.describe "Operations users", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let!(:target) { create(:user, email_address: "target@example.com", first_name: "Tess", last_name: "Target") }
  let!(:other) { create(:user, email_address: "other@example.com", first_name: "Otto", last_name: "Other") }

  before { sign_in(operator) }

  # A paginated list of every user (#1135), ordered by created_at because names are
  # encrypted non-deterministically (#1124).
  describe "GET /operations/users" do
    def rows_in(response) = Capybara.string(response.body).all("[data-testid='operations-user-row']")

    it "lists every user newest first, without a query" do
      get operations_users_path
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_text("Tess Target")
      expect(html).to have_text("Otto Other")
    end

    it "orders by creation, newest first" do
      newest = create(:user, first_name: "Nina", last_name: "Newest")
      get operations_users_path
      names = rows_in(response).map(&:text)
      expect(names.first).to include("Nina Newest")
      expect(names.join).to include("Tess Target")
      expect(User.order(created_at: :desc).first).to eq(newest)
    end

    # Pages, not any labelled nav: the operations layout's own nav also matches.
    it "paginates rather than rendering the whole instance" do
      stub_const("Pagy::OPTIONS", Pagy::OPTIONS.merge(limit: 2))
      create_list(:user, 3)
      get operations_users_path

      html = Capybara.string(response.body)
      expect(html).to have_css("nav[aria-label='#{I18n.t('pagination.aria_label')}']")
      expect(rows_in(response).size).to eq(2)
    end

    it "filters to the exact email match" do
      get operations_users_path(q: "Target@Example.com")
      html = Capybara.string(response.body)
      expect(html).to have_text("Tess Target")
      expect(html).to have_no_text("Otto Other")
    end

    # Names match by decrypting in Ruby, the only way into a non-deterministic column.
    it "filters by name, not only by address" do
      get operations_users_path(q: "tess")
      html = Capybara.string(response.body)
      expect(html).to have_text("Tess Target")
      expect(html).to have_no_text("Otto Other")
    end

    # Never a silent cap (#1166).
    it "says when names were too numerous to search" do
      stub_const("User::Search::NAME_SEARCH_LIMIT", 0)
      get operations_users_path(q: "tess")
      expect(Capybara.string(response.body))
        .to have_text(I18n.t("operations.users.index.names_skipped"))
    end

    it "says when the match list was capped" do
      stub_const("User::Search::RESULT_LIMIT", 1)
      get operations_users_path(q: "t")
      expect(Capybara.string(response.body))
        .to have_text(I18n.t("operations.users.index.capped", count: 1))
    end

    # .btn-cell-link sets no colour of its own — .btn-text-interactive is what
    # makes it read as a link rather than plain text (1.4.1).
    it "renders the found user's name link as visibly a link" do
      get operations_users_path(q: "Target@Example.com")
      link = Capybara.string(response.body).find_link("Tess Target")
      expect(link[:class]).to include("btn-text-interactive")
    end

    it "says so when nothing matches" do
      get operations_users_path(q: "nobody@example.com")
      expect(Capybara.string(response.body)).to have_text(I18n.t("operations.users.index.no_match"))
    end

    # The row carries the same state badges as the user's page, from one partial.
    it "renders a row with the address and every state badge the show page opens with" do
      Operatorship.grant!(user: target)
      target.update!(locked_at: Time.current)
      get operations_users_path(q: target.email_address)

      row = Capybara.string(response.body).find("[data-testid='operations-user-row']")
      expect(row).to have_link("Tess Target", href: operations_user_path(target))
      expect(row).to have_text(target.email_address)
      expect(row).to have_css("span[data-variant='soft']", text: I18n.t("operations.users.show.operator"))
      expect(row).to have_css("span[data-variant='soft']", text: I18n.t("operations.users.show.locked_out"))
    end

    it "hands a miss to the ledger, whose search also matches workspaces and projects" do
      get operations_users_path(q: "nobody@example.com")
      expect(Capybara.string(response.body)).to have_link(I18n.t("operations.users.index.search_activity"),
        href: operations_activity_logs_path(q: "nobody@example.com"))
    end
  end

  describe "GET /operations/users/:id" do
    it "shows memberships with roles, no badges, no lockout line, and a Suspend form for a plain user" do
      workspace = create(:workspace, name: "Acme")
      create(:membership, :admin, user: target, workspace: workspace)
      get operations_user_path(target)
      html = Capybara.string(response.body)
      expect(html).to have_text("Acme")
      expect(html).to have_text("Admin")
      # Scoped to #main-content, not the whole body: the operations nav's
      # own "Operators" link is a substring match on "Operator" otherwise.
      main = html.find("#main-content")
      expect(main).to have_no_text(I18n.t("operations.users.show.operator"))
      expect(main).to have_no_text(I18n.t("operations.users.show.suspended"))
      expect(html).to have_no_css("form[action='#{operations_user_lock_path(target)}']")
      expect(html).to have_css("form[action='#{operations_user_suspension_path(target)}']",
        text: I18n.t("operations.users.show.suspend"))
      expect(html).to have_no_css("form[action='#{operations_user_suspension_path(target)}']",
        text: I18n.t("operations.users.show.reinstate"))
    end

    # .btn-cell-link sets no colour of its own — .btn-text-interactive is what
    # makes it read as a link rather than plain text (1.4.1).
    it "renders a membership's workspace name link as visibly a link" do
      workspace = create(:workspace, name: "Acme")
      create(:membership, :admin, user: target, workspace: workspace)
      get operations_user_path(target)
      link = Capybara.string(response.body).find_link("Acme")
      expect(link[:class]).to include("btn-text-interactive")
    end

    it "shows the lockout sentence and a 'Let them try again' form only for a locked account, alongside the Suspend form" do
      freeze_time do
        5.times { target.register_failed_login! }
        get operations_user_path(target)
        html = Capybara.string(response.body)
        expect(html).to have_text(I18n.t("operations.users.show.lockout",
          count: User::MAX_FAILED_ATTEMPTS,
          time: ActionController::Base.helpers.distance_of_time_in_words(Time.current, target.reload.locked_at + User::LOCK_DURATION)))
        expect(html).to have_css("form[action='#{operations_user_lock_path(target)}']",
          text: I18n.t("operations.users.show.clear_lockout"))
        expect(html).to have_css("form[action='#{operations_user_suspension_path(target)}']",
          text: I18n.t("operations.users.show.suspend"))
      end
    end

    it "shows the Suspended badge, the since sentence in the operator's zone, and a Reinstate form — no Suspend form" do
      # A zone that differs from the test default (UTC), so the assertion
      # only passes if the view converts through the viewer's preference.
      (operator.preferences || operator.create_preferences!).update!(timezone: "America/Chicago")
      freeze_time do
        target.suspend!(by: operator)
        get operations_user_path(target)
        html = Capybara.string(response.body)
        expect(html).to have_text(I18n.t("operations.users.show.suspended"))
        expect(html).to have_text(I18n.t("operations.users.show.suspended_since_html",
          time: I18n.l(target.reload.suspended_at.in_time_zone("America/Chicago"), format: :account_activity)))
        expect(html).to have_css("form[action='#{operations_user_suspension_path(target)}']",
          text: I18n.t("operations.users.show.reinstate"))
        expect(html).to have_no_css("form[action='#{operations_user_suspension_path(target)}']",
          text: I18n.t("operations.users.show.suspend"))
      end
    end

    # Every state is a badge on the name line, the sentences follow, and the
    # controls share one row with the lockout clear (the transient state)
    # before the destructive suspend/reinstate. The confirm names the person.
    it "opens with the states as badges, the sentences after, and the controls in one row" do
      freeze_time do
        5.times { target.register_failed_login! }
        target.suspend!(by: operator)
        get operations_user_path(target)
        html = Capybara.string(response.body)
        header = html.find("main header")
        expect(header).to have_css("span[data-variant='soft']", text: I18n.t("operations.users.show.suspended"))
        expect(header).to have_css("span[data-variant='soft']", text: I18n.t("operations.users.show.locked_out"))
        expect(html).to have_css("time[datetime='#{target.reload.suspended_at.iso8601}']")
        actions = html.all("form[action='#{operations_user_lock_path(target)}'], form[action='#{operations_user_suspension_path(target)}']")
        expect(actions.map { |form| form[:action] })
          .to eq([ operations_user_lock_path(target), operations_user_suspension_path(target) ])
        expect(html).to have_link(I18n.t("operations.users.show.view_activity"),
          href: operations_activity_logs_path(q: target.email_address))
        expect(html).to have_title(I18n.t("operations.area.page_title", name: "Tess Target"))
      end
    end

    it "names the person in the suspend confirm" do
      get operations_user_path(target)
      form = Capybara.string(response.body).find("form[action='#{operations_user_suspension_path(target)}']")
      expect(form[:"data-turbo-confirm"]).to eq(I18n.t("operations.users.show.suspend_confirm", name: "Tess Target"))
    end

    # A locked workspace is the one reason "they can't get in" the membership
    # list would otherwise not show; an active one gets no chip.
    it "badges a membership in a locked workspace and leaves an active one plain" do
      locked = create(:workspace, name: "Frozen")
      locked.suspend!
      create(:membership, user: target, workspace: locked)
      create(:membership, user: target, workspace: create(:workspace, name: "Open"))

      get operations_user_path(target)
      list = Capybara.string(response.body).find("#ops-user-memberships")
      expect(list.find("li", text: "Frozen")).to have_css("span[data-variant='soft']", exact_text: "#{I18n.t("lifecycle_status.prefix")}: #{I18n.t("lifecycle_status.suspended")}")
      expect(list.find("li", text: "Open")).to have_no_css("span.sr-only", text: I18n.t("lifecycle_status.prefix"))
    end

    it "shows the Operator badge, no Suspend form, and the revoke-first sentence linking to the roster" do
      Operatorship.grant!(user: target)
      get operations_user_path(target)
      html = Capybara.string(response.body)
      expect(html).to have_text(I18n.t("operations.users.show.operator"))
      expect(html).to have_no_css("form[action='#{operations_user_suspension_path(target)}']")
      link = html.find_link(I18n.t("operations.users.show.operator_access"))
      expect(link[:href]).to eq(operations_operatorships_path)
      # An in-prose link, underlined — not the action-row .btn-text utility.
      expect(link[:class]).to include("underline")
      expect(link[:class]).not_to include("btn-text")
    end

    # SQLite's BINARY collation sorts uppercase before lowercase, so a plain
    # `.order("workspaces.name")` reads as alphabetical but isn't.
    # workspaces.name is a plain column (unlike User#first_name/#last_name,
    # which are non-deterministically encrypted and can be neither searched
    # nor ORDER BY'd in SQL), so this can be fixed in SQL rather than sorted
    # in Ruby.
    it "orders memberships by workspace name case-insensitively" do
      create(:membership, user: target, workspace: create(:workspace, name: "zeta"))
      create(:membership, user: target, workspace: create(:workspace, name: "Acme"))
      create(:membership, user: target, workspace: create(:workspace, name: "beta"))
      create(:membership, user: target, workspace: create(:workspace, name: "Delta"))

      get operations_user_path(target)

      # Scoped to the membership list, not the whole body: target's own
      # onboarding workspace is in this list under a Faker name, and a raw
      # body.index search matched it first whenever that name happened to
      # contain one of these tokens (deterministic failure on seed 58938).
      # Array#& keeps the receiver's order, so this reads the rendered order
      # and ignores the unrelated row.
      rendered = Capybara.string(response.body)
                         .find("#ops-user-memberships")
                         .all("li a").map(&:text)
      # Binary collation would read Acme, Delta, beta, zeta (uppercase first).
      # Case-insensitive alphabetical is Acme, beta, Delta, zeta.
      expect(rendered & %w[Acme beta Delta zeta]).to eq(%w[Acme beta Delta zeta])
    end
  end

  describe "DELETE /operations/users/:id/lock" do
    it "unlocks and writes a user.unlocked row naming the operator" do
      5.times { target.register_failed_login! }
      expect(target.reload).to be_locked
      delete operations_user_lock_path(target)
      expect(target.reload).not_to be_locked
      expect(response).to redirect_to(operations_user_path(target))
      expect(flash[:notice]).to eq(I18n.t("operations.users.locks.destroy.success"))
      row = ActivityLog.find_by!(action: "user.unlocked", trackable: target)
      expect(row.actor).to eq(operator)
    end
  end

  describe "POST /operations/users/:id/suspension" do
    it "suspends access, ends sessions, and leaves memberships kept" do
      workspace = create(:workspace)
      create(:membership, :owner, user: target, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      target.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

      expect {
        post operations_user_suspension_path(target)
      }.not_to change { target.memberships.kept.count }

      expect(target.reload).to be_suspended
      expect(target.sessions.count).to eq(0)
      expect(flash[:notice]).to eq(I18n.t("operations.users.suspensions.create.success"))
    end

    it "refuses to suspend an operator" do
      Operatorship.grant!(user: target)

      post operations_user_suspension_path(target)

      expect(target.reload).not_to be_suspended
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end
  end

  describe "DELETE /operations/users/:id/suspension" do
    it "reinstates access" do
      target.suspend!(by: operator)

      delete operations_user_suspension_path(target)

      expect(target.reload).not_to be_suspended
      expect(response).to redirect_to(operations_user_path(target))
      expect(flash[:notice]).to eq(I18n.t("operations.users.suspensions.destroy.success"))
    end
  end
end
