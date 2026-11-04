# frozen_string_literal: true

require "rails_helper"

# System spec for the workspace switcher, which heads the workspace sidebar.
#
# It therefore only exists on workspace pages — the sidebar is the switcher's
# home, so this visits one rather than the workspaces index. The sidebar is
# `hidden md:flex`; the default viewport satisfies that, no resize needed.
RSpec.describe "Workspace switcher (sidebar)", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let!(:second) do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before do
    sign_in_via_form(user)
    # Start on the OTHER workspace so selecting `second` is a real navigation
    # rather than a click that lands where we already are.
    visit workspace_path(user.personal_workspace)
  end

  it "opens on click, lists both workspaces, and navigates on selection" do
    button = find("#workspace-switcher-button")
    expect(button["aria-expanded"]).to eq("false")

    button.click
    expect(button["aria-expanded"]).to eq("true")

    within "#workspace-switcher-menu" do
      expect(page).to have_link(second.name)
      click_link second.name
    end

    expect(page).to have_current_path(workspace_path(second))
  end

  it "closes on Escape" do
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    cdp_press("Escape")

    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#workspace-switcher-menu", visible: :visible)
  end

  it "is accessible with the menu open (wcag2aaa-scoped, both themes)" do
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
