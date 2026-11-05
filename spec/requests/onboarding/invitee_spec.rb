require "rails_helper"

# Under :none an invitee is not a first-run user — the wizard exists for the
# self-signup who has nowhere to go. Left unstamped, an invited Member was
# funnelled into the invite step, refused by InvitationPolicy, redirected to
# the workspace, and funnelled again: "redirected you too many times".
RSpec.describe "Onboarding · invitees", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  let(:owner) { create(:user, :with_zero_workspaces, onboarded_at: Time.current) }
  let(:workspace) { create(:workspace) }
  # Membership before project: the project factory seats its creator.
  let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
  let!(:project) { create(:project, workspace: workspace, created_by: owner) }
  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end
  let!(:admin_role) do
    Role.find_or_create_by!(slug: "admin", workspace_id: nil) do |r|
      r.name = "Admin"
      r.permissions = { manage_members: true, manage_projects: true, manage_settings: true }
    end
  end
  let(:invitee) { create(:user, :with_zero_workspaces) }

  def accept_as(role)
    create(:invitation, invitable: workspace, role: role, invited_by: owner, email: invitee.email_address)
      .accept!(invitee)
  end

  it "lands an invited Member on their workspace, never in the wizard" do
    accept_as(member_role)
    sign_in(invitee)

    get new_session_path
    expect(response).not_to redirect_to(onboarding_path)
    get workspace_path(workspace)
    expect(response).to have_http_status(:ok)
    expect(invitee.reload).to be_onboarded
  end

  it "shows an invited Admin no first-run wizard for a workspace they did not set up" do
    accept_as(admin_role)
    sign_in(invitee)

    get new_onboarding_team_path
    expect(response).to redirect_to(root_path)
  end

  # Data that predates the stamp, or any future refusal inside the wizard: a
  # refused step leaves the wizard for good instead of bouncing back into it.
  it "leaves the wizard on a refusal instead of bouncing back into it" do
    accept_as(member_role)
    invitee.update_column(:onboarded_at, nil)
    sign_in(invitee)

    get new_onboarding_team_path
    expect(response).to redirect_to(workspace_path(workspace))
    expect(invitee.reload).to be_onboarded
    get workspace_path(workspace)
    expect(response).to have_http_status(:ok)
  end
end
