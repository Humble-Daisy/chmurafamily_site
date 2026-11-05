# frozen_string_literal: true

require "rails_helper"

# Regression guard for the toast containers' landmark semantics
# (app/views/shared/_toasts.html.erb). These examples deliberately run
# UNSCOPED — whole page, layout chrome included — so a violation on the
# always-rendered containers can never come back unnoticed behind a
# narrowed `include:`.
#
# Per-spec axe runs at the default rule level locally; AAA is a CI-only
# claim (see spec/support/axe_accessibility.rb) — do not claim AAA
# from a local run.
RSpec.describe "Toast containers — axe landmark audit", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  it "page with a live toast is axe-clean, chrome included (both themes)" do
    sign_in_via_form(user)

    expect(axe_clean_in_both_themes?).to be(true),
      "violations with a live toast: #{axe_violations_in_both_themes.join("\n")}"
  end

  it "empty toast containers are axe-clean, chrome included (both themes)" do
    visit "/docs"
    expect(page).to have_css("#toast-pills", visible: :all)

    expect(axe_clean_in_both_themes?).to be(true),
      "violations with empty containers: #{axe_violations_in_both_themes.join("\n")}"
  end
end
