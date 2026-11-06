require "rails_helper"

RSpec.describe "Operations workspaces", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:owner) { create(:user, first_name: "Olive", last_name: "Owner") }
  let(:workspace) { create(:workspace, name: "Acme") }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    sign_in(operator)
  end

  describe "GET /operations/workspaces" do
    # The index is where /operations lands, so it is the area's primary
    # route to a workspace. Without this link, show is reachable only from
    # a user's page or the activity feed.
    it "links each workspace to its own page" do
      get operations_workspaces_path
      expect(Capybara.string(response.body))
        .to have_link("Acme", href: operations_workspace_path(workspace))
    end

    # .btn-cell-link sets no colour of its own — .btn-text-interactive is what
    # makes it read as a link rather than plain table text (1.4.1).
    it "renders the workspace name link as visibly a link" do
      get operations_workspaces_path
      link = Capybara.string(response.body).find_link("Acme")
      expect(link[:class]).to include("btn-text-interactive")
    end

    # SQLite's default BINARY collation sorts every uppercase-initial name
    # before every lowercase one — matches the sibling fix on
    # Operations::UsersController#show (Arel.sql("LOWER(workspaces.name)")).
    it "orders case-insensitively rather than uppercase-first" do
      # "Acme" (the outer `let!`) sorts BEFORE every lowercase name under
      # SQLite's default BINARY collation, which is the defect: a
      # case-insensitive sort interleaves it as "amber, beta, Zebra Corp".
      create(:workspace, name: "beta")
      create(:workspace, name: "Zebra Corp")
      create(:workspace, name: "amber")
      relevant = [ "amber", "beta", workspace.name, "Zebra Corp" ]

      get operations_workspaces_path
      # Onboarding gives `operator`/`owner` their own workspaces too (random
      # Faker names) — scope down to just the rows this example created.
      all_names = Capybara.string(response.body).all("tbody tr th[scope=row]").map { |th| th.text.strip }
      names = all_names.select { |name| relevant.include?(name) }

      expect(names).to eq(relevant.sort_by(&:downcase))
    end

    # Only the name column carries a link (the other three are plain text),
    # so a keyboard user tabbing through the page skips straight over this
    # table without ever reaching Status/Owner/Members — axe has no rule for
    # an unreachable scroll region, so this asserts the ScrollArea contract's
    # attributes directly (spec/system/responsive/tables_overflow_spec.rb is
    # the sibling tables' geometry-level proof).
    it "wraps the table in a focusable, named scroll region a keyboard user can reach" do
      get operations_workspaces_path
      label = I18n.t("modelrails_ui.table.scroll_region", name: I18n.t("operations.workspaces.index.caption"))
      region = Capybara.string(response.body).find("[role='region'][aria-label='#{label}']")

      expect(region[:tabindex]).to eq("0")
      expect(region[:class]).to include("focus-ring")
      expect(region).to have_css("table")
    end

    # The name cell is the row's identity: a row header, so cell-by-cell
    # navigation hears which workspace a status or count belongs to. Every
    # cell is nowrap, or the w-full table compresses instead of scrolling at
    # phone width. Status renders through the one badge treatment.
    it "renders each row with a row header, nowrap cells and a status badge" do
      get operations_workspaces_path
      row = Capybara.string(response.body).find("tbody tr", text: "Acme")
      expect(row).to have_css("th[scope=row]", text: "Acme")
      expect(row.all("th, td").map { |cell| cell[:class] }).to all(include("whitespace-nowrap"))
      expect(row).to have_css("td span[data-variant='soft']", exact_text: "#{I18n.t("lifecycle_status.prefix")}: #{I18n.t("lifecycle_status.active")}")
    end

    # Membership#owner? has no kept test, so a discarded owner membership
    # (suspend-access produces exactly this) would otherwise still show
    # that person as Owner beside a member count of zero — disagreeing with
    # show, which is built from memberships.kept.
    it "does not credit a discarded membership's user as Owner" do
      Membership.kept.find_by!(user: owner, workspace: workspace).update!(discarded_at: Time.current)

      get operations_workspaces_path
      html = Capybara.string(response.body)
      row = html.find("tr", text: "Acme")
      expect(row).to have_no_text("Olive Owner")
      expect(row).to have_text("0")
    end

    # The list renders through UI::TableComponent: the caption is the table's
    # accessible name (sr-only), every header cell is a column header, and the
    # pagination footer sits inside the component's bordered wrapper.
    it "renders the workspaces list through the table component" do
      create(:workspace, name: "Alpha")

      get operations_workspaces_path
      html = Capybara.string(response.body)
      expect(html).to have_css("div[data-size] table caption.sr-only", text: I18n.t("operations.workspaces.index.caption"))
      expect(html.all("thead th").size).to eq(html.all("thead th[scope=col]").size)
      expect(html).to have_css("div[data-size] > div[role=region] > table")
    end
  end

  # Operators honor deploy-time tenancy posture — mirrors
  # spec/requests/workspaces_spec.rb's tenant-side coverage.
  describe "workspace creation disabled (TENANCY_WORKSPACE_CREATION=disabled)" do
    before do
      allow(Rails.configuration.x.tenancy).to receive(:workspace_creation).and_return(:disabled)
    end

    it "omits the new-workspace control from an index that otherwise renders" do
      get operations_workspaces_path
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_link("Acme", href: operations_workspace_path(workspace))
      expect(html).to have_no_link(href: new_operations_workspace_path)
    end

    # The gate registers after BaseController's require_operator, so a
    # non-operator still learns nothing — not even that creation is off.
    it "still answers 404 to a non-operator rather than the creation-disabled redirect" do
      sign_in(create(:user))
      get new_operations_workspace_path
      expect(response).to have_http_status(:not_found)
    end

    it "redirects GET /operations/workspaces/new to root with an alert" do
      get new_operations_workspace_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
    end

    it "refuses POST /operations/workspaces" do
      expect {
        post operations_workspaces_path, params: { workspace: { name: "Blocked Co", owner_email: owner.email_address } }
      }.not_to change(Workspace, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
    end
  end

  describe "workspace creation enabled (the default)" do
    it "renders the new-workspace control on the index" do
      get operations_workspaces_path
      expect(Capybara.string(response.body)).to have_link(href: new_operations_workspace_path)
    end
  end

  describe "GET /operations/workspaces/:slug" do
    # The name line carries the status badge; the one navigation link sits
    # beside it; the lock control closes the page under its own heading with
    # a confirm that names what it locks. Lists carry role=list (the preflight
    # strips the implicit role). The tab title says which side of the app it is.
    it "opens with the badge on the name line, links into the ledger, and keeps the lock control last" do
      get operations_workspace_path(workspace)
      html = Capybara.string(response.body)
      header = html.find("main header")
      expect(header).to have_css("h1", text: "Acme")
      expect(header).to have_css("span[data-variant='soft']", exact_text: "#{I18n.t("lifecycle_status.prefix")}: #{I18n.t("lifecycle_status.active")}")
      expect(html).to have_link(I18n.t("operations.workspaces.show.view_activity"),
        href: operations_activity_logs_path(workspace: workspace.slug))
      expect(html.all("h2").map(&:text).last).to eq(I18n.t("operations.workspaces.show.access"))
      form = html.find("form[action='#{operations_workspace_suspension_path(workspace)}']")
      expect(form[:"data-turbo-confirm"]).to eq(I18n.t("operations.workspaces.show.suspend_confirm", name: "Acme"))
      expect(html).to have_css("#ops-members ul[role=list]")
      expect(html).to have_no_css("section[aria-labelledby]")
      expect(html).to have_title(I18n.t("operations.area.page_title", name: "Acme"))
    end

    it "says since when a locked workspace has been locked, as a <time>, beside the unlock control" do
      freeze_time do
        workspace.suspend!
        get operations_workspace_path(workspace)
        html = Capybara.string(response.body)
        expect(html).to have_css("time[datetime='#{workspace.reload.suspended_at.iso8601}']")
        expect(html).to have_text(I18n.t("operations.workspaces.show.locked_since_html",
          time: I18n.l(workspace.suspended_at.in_time_zone(Time.zone), format: :account_activity)))
        expect(html).to have_css("form[action='#{operations_workspace_suspension_path(workspace)}']",
          text: I18n.t("operations.workspaces.show.unsuspend"))
      end
    end

    it "shows members with roles" do
      get operations_workspace_path(workspace)
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_text("Olive Owner")
      # A bare have_text("Owner") is satisfied by the owner's own name
      # ("Olive Owner") whether or not the role badge renders at all — scope
      # to the members list's role badge so this actually proves the role
      # is shown (the activity feed below also mentions "Olive Owner").
      members = html.find("#ops-members")
      row = members.find("li", text: "Olive Owner")
      expect(row).to have_css("span[data-variant='soft'][data-tone='neutral']", text: "Owner")
    end

    it "orders members by name, not creation order or an SQL sort on encrypted columns" do
      # first_name/last_name are non-deterministically encrypted, so this
      # must be created in an order where insertion order (and any
      # accidental sort on ciphertext) disagrees with alphabetical order —
      # otherwise the assertion below would pass by coincidence.
      create(:membership, user: create(:user, first_name: "Zoe", last_name: "Young"), workspace: workspace)
      create(:membership, user: create(:user, first_name: "Amy", last_name: "Adams"), workspace: workspace)
      create(:membership, user: create(:user, first_name: "Ben", last_name: "Baker"), workspace: workspace)

      get operations_workspace_path(workspace)

      # The member list itself, in DOM order; the badge span is excluded (#1231).
      names = Capybara.string(response.body).all("#ops-members li span:not([data-variant])").map(&:text)

      # Inserted out of order, so only a sort by decrypted last name passes.
      expect(names).to eq([ "Amy Adams", "Ben Baker", "Olive Owner", "Zoe Young" ])
    end

    it "renders a suspended workspace instead of bouncing" do
      workspace.suspend!
      get operations_workspace_path(workspace)
      expect(response).to have_http_status(:ok)
      # lifecycle.en.yml roots this key under lifecycle_status, not
      # lifecycle.status.
      expect(Capybara.string(response.body)).to have_text(I18n.t("lifecycle_status.suspended"))
    end

    it "redirects to root with a not-found alert for a discarded workspace" do
      # record_not_found (ApplicationController) redirects HTML requests to
      # the referer or root; a request spec sends no referer, so root is
      # the one real outcome here.
      workspace.discard!
      get operations_workspace_path(workspace)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end

    # `<a href data-turbo-method>` would be a GET fallback with no route,
    # and a destructive state change announced as a link. `button_to` is
    # the app's own convention for every other confirm-guarded mutation.
    it "renders the suspend control as a form, not a link" do
      get operations_workspace_path(workspace)
      html = Capybara.string(response.body)
      path = operations_workspace_suspension_path(workspace)
      expect(html).to have_no_link(href: path)
      expect(html).to have_css("form[action='#{path}']", text: I18n.t("operations.workspaces.show.suspend"))
    end

    it "renders the unsuspend control as a form, not a link" do
      workspace.suspend!
      get operations_workspace_path(workspace)
      html = Capybara.string(response.body)
      path = operations_workspace_suspension_path(workspace)
      expect(html).to have_no_link(href: path)
      expect(html).to have_css("form[action='#{path}']", text: I18n.t("operations.workspaces.show.unsuspend"))
    end
  end

  describe "POST/DELETE /operations/workspaces/:slug/suspension" do
    it "suspends and writes a workspace-visible row with the operator as actor" do
      expect {
        post operations_workspace_suspension_path(workspace)
      }.to change { workspace.reload.suspended? }.from(false).to(true)
      expect(response).to redirect_to(operations_workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("operations.workspaces.suspensions.create.success"))

      row = workspace.activity_logs.order(:id).last
      expect(row.visibility).to eq("workspace")
      expect(row.actor).to eq(operator)
      expect(row.display_action).to eq("workspace.suspended")
    end

    it "unsuspends" do
      workspace.suspend!
      expect {
        delete operations_workspace_suspension_path(workspace)
      }.to change { workspace.reload.suspended? }.from(true).to(false)
      expect(flash[:notice]).to eq(I18n.t("operations.workspaces.suspensions.destroy.success"))
    end

    # A repeat POST on an already-suspended workspace must not bump
    # suspended_at to a new timestamp or write a second "locked" entry into
    # the tenant's feed.
    it "does not duplicate the activity row or bump the timestamp on a repeat suspend" do
      workspace.suspend!
      suspended_at = workspace.reload.suspended_at

      expect {
        post operations_workspace_suspension_path(workspace)
      }.not_to change { workspace.activity_logs.count }
      expect(workspace.reload.suspended_at).to eq(suspended_at)
      expect(response).to redirect_to(operations_workspace_path(workspace))
    end

    # A no-op unsuspend! (suspended_at already nil) writes no activity row and
    # doesn't bump updated_at, so neither one can tell a guarded destroy from
    # an unguarded one — the only observable difference is Broadcastable's
    # after_update_commit, which fires even on a no-op save. The broadcast
    # expectation below is what actually fails if Suspendable#unsuspend!'s
    # `next :not_suspended` guard is removed; the rest would pass either way.
    it "reports the unlocked state without writing a row when it is not suspended" do
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_refresh_to)

      expect {
        delete operations_workspace_suspension_path(workspace)
      }.not_to change { workspace.activity_logs.count }
      expect(workspace.reload.suspended_at).to be_nil
      expect(response).to redirect_to(operations_workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("operations.workspaces.suspensions.destroy.success"))
    end

    it "shows the tenant's owner the operator's action in the workspace feed" do
      post operations_workspace_suspension_path(workspace)
      workspace.unsuspend!
      sign_in(owner)
      get workspace_path(workspace)
      # A plain have_text substring check for "locked" is satisfied by the
      # "UNlocked" row too, since the unsuspend above is what lets this page
      # load at all; the negative lookbehind is what tells the two apart.
      # `Vocabulary.tokens[:workspace]`, not a literal "workspace" string, so
      # a fork that renamed the noun (config/initializers/vocabulary.rb) still
      # gets a real assertion. Both expectations below target the SAME <li>,
      # so an inverted ternary — the operator named on the mislabeled
      # "unlocked" row — can't pass either.
      locked_row_regex = /(?<!un)locked the #{Regexp.escape(Vocabulary.tokens[:workspace])}/
      row = Capybara.string(response.body).all("li").find { |li| li.text.match?(locked_row_regex) }
      expect(row).to be_present, "no activity row read \"locked the #{Vocabulary.tokens[:workspace]}\" (not \"unlocked\")"
      expect(row).to have_text(operator.full_name)
    end
  end

  describe "POST /operations/workspaces" do
    it "creates a workspace owned by an existing user" do
      expect {
        post operations_workspaces_path, params: { workspace: { name: "New Co", owner_email: owner.email_address } }
      }.to change(Workspace, :count).by(1)
      created = Workspace.order(:id).last
      expect(created.owners).to contain_exactly(owner)
      expect(response).to redirect_to(operations_workspace_path(created))
      expect(flash[:notice]).to eq(I18n.t("operations.workspaces.create.success"))
    end

    it "creates a workspace owned by the operator and invites an unknown email as Owner" do
      expect {
        post operations_workspaces_path, params: { workspace: { name: "Fresh Co", owner_email: "fresh@example.com" } }
      }.to change(Workspace, :count).by(1).and change(Invitation, :count).by(1)
      created = Workspace.order(:id).last
      expect(created.owners).to contain_exactly(operator)
      invitation = created.invitations.sole
      expect(invitation.email).to eq("fresh@example.com")
      expect(invitation.role.slug).to eq("owner")
      expect(invitation.invited_by).to eq(operator)
    end

    it "re-renders on a blank name" do
      post operations_workspaces_path, params: { workspace: { name: "", owner_email: owner.email_address } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Invitation.bulk_invite! does not raise on a malformed/blank email — it
    # silently skips it (issuance.rb's own EMAIL_FORMAT check increments
    # `skipped`; `sent` is never decremented anywhere). Left unguarded, a
    # blank owner_email would quietly hand the new workspace to the OPERATOR
    # with no invitation and no error shown.
    it "re-renders on a blank owner_email rather than silently handing the workspace to the operator" do
      expect {
        post operations_workspaces_path, params: { workspace: { name: "Orphan Co", owner_email: "" } }
      }.to change(Workspace, :count).by(0).and change(Invitation, :count).by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # owner_email is a real (virtual) Workspace attribute, so the error
    # attaches to the FIELD, not :base, and the form builder wires
    # aria-invalid/describedby onto it.
    it "marks the owner_email field invalid, with aria-describedby pointing at the message" do
      post operations_workspaces_path, params: { workspace: { name: "Orphan Co", owner_email: "not-an-email" } }
      html = Capybara.string(response.body)
      field = html.find_field("workspace_owner_email")
      expect(field["aria-invalid"]).to eq("true")

      described_by = field["aria-describedby"]
      expect(described_by).to be_present
      expect(html).to have_selector("##{described_by}",
        text: I18n.t("activerecord.errors.models.workspace.attributes.owner_email.invalid"))

      # full_message (used by the error summary) prefixes human_attribute_name,
      # not the field's own label — pin the two together so the summary's
      # skip link never lands on a field labelled differently.
      expect(Workspace.human_attribute_name(:owner_email)).to eq(I18n.t("operations.workspaces.new.owner_email"))
    end

    # create_for_owner_email returns the invalid record it validated, so the
    # form re-renders with the submitted owner_email still in the field; a
    # bare Workspace.new before render would blank it.
    it "re-renders a malformed owner_email with the submitted value still in the field" do
      post operations_workspaces_path, params: { workspace: { name: "Orphan Co", owner_email: "not-an-email" } }
      html = Capybara.string(response.body)
      expect(html.find_field("workspace_owner_email").value).to eq("not-an-email")
    end
  end
end
