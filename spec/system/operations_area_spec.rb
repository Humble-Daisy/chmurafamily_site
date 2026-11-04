# frozen_string_literal: true

require "rails_helper"

# The WCAG 2.2 AAA gate over the whole instance-operations area, both themes.
#
# Every I18n.t call below passes no vocabulary noun keyword (workspace:,
# project:) — the backend injects %{workspace}/%{workspaces}/etc itself, and
# a caller's literal would win over it and stop discriminating in a fork
# that renamed the noun. See /docs/developer/i18n (Vocabulary).
#
# :with_zero_workspaces keeps the operator's own workspace list genuinely
# empty — the default trait onboards a personal workspace, which would make
# "no workspaces yet" unreachable.
RSpec.describe "Operations area", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in_via_form(operator) }

  it "lists workspaces, empty then populated, with the area banner, AAA in both themes" do
    visit operations_workspaces_path
    expect(page).to have_text(I18n.t("operations.area.banner"))
    expect(page).to have_text(I18n.t("operations.workspaces.index.empty"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    owner = create(:user, first_name: "Olive", last_name: "Owner")
    workspace = create(:workspace, name: "Acme Robotics")
    create(:membership, :owner, user: owner, workspace: workspace)

    visit operations_workspaces_path
    expect(page).to have_text("Acme Robotics")
    expect(page).to have_text("Olive Owner")
    expect(page).to have_text(I18n.t("lifecycle_status.active"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers both lock states so the lock control AND the unlock control are
  # each audited, plus the status badge's rendered aria-label.
  it "shows a workspace, locks and unlocks it, auditing both states and the status badge, AAA in both themes" do
    owner = create(:user, first_name: "Olive", last_name: "Owner")
    workspace = create(:workspace, name: "Acme Robotics")
    create(:membership, :owner, user: owner, workspace: workspace)

    # Reached by clicking through the index, not by visiting the route: the
    # index is where /operations lands, so this is the operator's real path
    # to a workspace.
    visit operations_workspaces_path
    click_link "Acme Robotics"
    expect(page).to have_current_path(operations_workspace_path(workspace))
    expect(page).to have_text(owner.full_name)
    expect(page).to have_css(
      "span[data-variant='soft']", exact_text: "#{I18n.t('lifecycle_status.prefix')}: #{I18n.t('lifecycle_status.active')}", normalize_ws: true
    )
    expect(page).to have_button(I18n.t("operations.workspaces.show.suspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Lock control: button_to with data-turbo-confirm on the form.
    accept_confirm(I18n.t("operations.workspaces.show.suspend_confirm", name: workspace.name)) { click_button I18n.t("operations.workspaces.show.suspend") }
    expect(page).to have_text(I18n.t("operations.workspaces.suspensions.create.success"))
    expect(workspace.reload).to be_suspended
    expect(page).to have_css(
      "span[data-variant='soft']", exact_text: "#{I18n.t('lifecycle_status.prefix')}: #{I18n.t('lifecycle_status.suspended')}", normalize_ws: true
    )
    expect(page).to have_button(I18n.t("operations.workspaces.show.unsuspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Unlock control: no confirm on this form (view has no data-turbo-confirm
    # on the unsuspend button_to), so a plain click_button is correct here.
    click_button I18n.t("operations.workspaces.show.unsuspend")
    expect(page).to have_text(I18n.t("operations.workspaces.suspensions.destroy.success"))
    expect(workspace.reload).not_to be_suspended
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "lists and filters users — unfiltered, a match, and no match, AAA in both themes" do
    target = create(:user, email_address: "target@example.com", first_name: "Tess", last_name: "Target")

    visit operations_users_path
    expect(page).to have_link(target.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.users.index.search_label"), with: target.email_address
    click_button I18n.t("operations.users.index.search")
    expect(page).to have_link(target.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.users.index.search_label"), with: "nobody@example.com"
    click_button I18n.t("operations.users.index.search")
    expect(page).to have_text(I18n.t("operations.users.index.no_match"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers the lockout sentence + "Let them try again" control, then the
  # Suspend/Reinstate cycle and the Suspended badge. The target's own
  # onboarding membership supplies a non-empty memberships list for free.
  it "shows a locked user, clears the lockout, then suspends and reinstates them, AAA in both themes" do
    target = create(:user, first_name: "Tess", last_name: "Target")
    5.times { target.register_failed_login! }

    visit operations_user_path(target)
    expect(page).to have_text(I18n.t("operations.users.show.lockout",
      count: User::MAX_FAILED_ATTEMPTS,
      time: ActionController::Base.helpers.distance_of_time_in_words(Time.current, target.reload.locked_at + User::LOCK_DURATION)))
    expect(page).to have_button(I18n.t("operations.users.show.clear_lockout"))
    # Pointer on a membership row: a static list_group_item highlights on
    # hover unless told not to, and text-interactive over that highlight is
    # below AAA — so the row is audited hovered, not at rest.
    page.find("#ops-user-memberships li", match: :first).hover
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Clear-lockout control: no confirm on this form.
    click_button I18n.t("operations.users.show.clear_lockout")
    expect(page).to have_text(I18n.t("operations.users.locks.destroy.success"))
    expect(target.reload).not_to be_locked
    expect(page).to have_no_button(I18n.t("operations.users.show.clear_lockout"))
    # After each click the cursor rests wherever the reflow left it — often on
    # a membership row. That is a state a real visitor reaches too, so it is
    # scored, not parked.
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Suspend control: button_to with data-turbo-confirm on the form.
    accept_confirm(I18n.t("operations.users.show.suspend_confirm", name: target.full_name)) { click_button I18n.t("operations.users.show.suspend") }
    expect(page).to have_text(I18n.t("operations.users.suspensions.create.success"))
    expect(page).to have_text(I18n.t("operations.users.show.suspended"))
    expect(page).to have_button(I18n.t("operations.users.show.reinstate"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Reinstate control: no confirm on this form.
    click_button I18n.t("operations.users.show.reinstate")
    expect(page).to have_text(I18n.t("operations.users.suspensions.destroy.success"))
    expect(page).to have_button(I18n.t("operations.users.show.suspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # Covers the grant form and the revoke button.
  it "grants and revokes an operator from the roster, AAA in both themes" do
    grantee = create(:user, first_name: "Sam", last_name: "Second")

    visit operations_operatorships_path
    expect(page).to have_text(operator.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    fill_in I18n.t("operations.operatorships.index.grant_label"), with: grantee.email_address
    click_button I18n.t("operations.operatorships.index.grant")
    expect(page).to have_text(I18n.t("operations.operatorships.create.success"))
    expect(grantee.reload).to be_operator
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Revoke control: button_to with data-turbo-confirm on the form.
    # Two identically-labelled "Revoke" buttons now exist on the roster, so
    # the click is scoped to the grantee's own row to disambiguate.
    within("li", text: grantee.full_name) do
      accept_confirm(I18n.t("operations.operatorships.index.revoke_confirm", name: grantee.full_name)) do
        click_button I18n.t("operations.operatorships.index.revoke")
      end
    end
    expect(page).to have_text(I18n.t("operations.operatorships.destroy.success"))
    expect(grantee.reload).not_to be_operator
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # 55 distinct workspaces mirrors spec/requests/operations/activity_logs_spec.rb's
  # own pagination example — each plain `create(:workspace, ...)` writes one
  # workspace-visible "workspace.created" row, crossing the ledger's own 50-row
  # default (ActivityLogsController::DEFAULT_ROWS, not Pagy::OPTIONS[:limit]),
  # so this proves the paginated state itself is AAA-clean, not just page one.
  it "shows the cross-workspace activity feed, including its paginated state, AAA in both themes" do
    55.times { |i| create(:workspace, name: format("WS %02d", i)) }

    visit operations_activity_logs_path
    expect(page).to have_css("nav.series-nav")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Scoped to the pager: the footer's Rows links sit beside it and "25"
    # contains "2", which an unscoped substring match calls ambiguous.
    within("nav.series-nav") { click_link "2" }
    expect(page).to have_css('[aria-current="page"]', text: "2")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  it "creates a workspace via the form, clean and its 422 error state, AAA in both themes" do
    visit new_operations_workspace_path
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Malformed, not blank: forms render novalidate (#1117).
    fill_in I18n.t("operations.workspaces.new.name"), with: "New Co"
    fill_in I18n.t("operations.workspaces.new.owner_email"), with: "not-an-email"
    click_button I18n.t("operations.workspaces.new.submit")
    expect(page).to have_text(I18n.t("activerecord.errors.models.workspace.attributes.owner_email.invalid"))
    expect(Workspace.find_by(name: "New Co")).to be_nil
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # States the gate never reached: an operator's own page (the branch that
  # refuses suspension and links to the roster instead), and the stacked
  # phone-width layouts of the empty list, the roster and a user page.
  # Last in the file — it resizes the shared window.
  it "audits an operator's own page and the phone-width layouts, AAA in both themes" do
    fellow = create(:user, :with_zero_workspaces, first_name: "Fern", last_name: "Fellow").tap { |u| Operatorship.grant!(user: u) }

    visit operations_user_path(fellow)
    expect(page).to have_link(I18n.t("operations.users.show.operator_access"))
    expect(page).to have_no_button(I18n.t("operations.users.show.suspend"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    page.current_window.resize_to(390, 1000)
    visit operations_workspaces_path
    expect(page).to have_text(I18n.t("operations.workspaces.index.empty"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    visit operations_operatorships_path
    expect(page).to have_text(fellow.full_name)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    visit operations_user_path(fellow)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
end
