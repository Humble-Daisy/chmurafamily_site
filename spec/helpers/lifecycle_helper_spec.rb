require "rails_helper"

RSpec.describe LifecycleHelper, type: :helper do
  # The vocabulary rule: "suspended"/"discarded" are internal names only.
  # This helper is the sole legal display path for lifecycle state.
  it "maps every status symbol to its user-facing label" do
    workspace = create(:workspace)
    expect(helper.lifecycle_status_label(workspace)).to eq("Active")

    workspace.archive!
    expect(helper.lifecycle_status_label(workspace)).to eq("Archived")

    workspace.suspend!
    expect(helper.lifecycle_status_label(workspace)).to eq("Locked")

    workspace.unsuspend!
    workspace.discard!
    expect(helper.lifecycle_status_label(workspace)).to eq("Deleted")
  end

  # One status treatment for the operations pages: the same soft badge whether
  # the record is a page title, a table cell or a membership row, with an
  # explicit "Status:" accessible name because the word alone ("Locked")
  # carries no context. A lock is the one state an operator acts on, so it
  # alone takes the warning tint — the tone the user page already gives
  # "Suspended".
  describe "#lifecycle_status_badge" do
    it "renders the label as a soft badge named as a status" do
      workspace = create(:workspace)
      html = Capybara.string(helper.lifecycle_status_badge(workspace))
      badge = html.find("span[data-variant='soft']", text: "Active")
      expect(badge[:"data-tone"]).to eq("neutral")
      expect(badge.text(normalize_ws: true)).to eq("#{I18n.t('lifecycle_status.prefix')}: Active")
      expect(badge.find("span.sr-only").text).to start_with(I18n.t("lifecycle_status.prefix"))
      expect(badge[:"aria-label"]).to be_nil
    end

    it "tints a locked record as a warning" do
      workspace = create(:workspace)
      workspace.suspend!
      badge = Capybara.string(helper.lifecycle_status_badge(workspace)).find("span[data-variant='soft']", text: "Locked")
      expect(badge[:"data-tone"]).to eq("warning")
    end
  end

  it "defines all four lifecycle_status keys (no titleize fallback possible)" do
    %w[active archived suspended discarded].each do |status|
      expect(I18n.exists?("lifecycle_status.#{status}")).to be(true),
        "missing lifecycle_status.#{status} — labels must come from I18n, never status.to_s"
    end
  end

  it "no view or helper titleizes/humanizes a lifecycle status (vocabulary leak guard)" do
    offenders = Dir[Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")].filter_map do |file|
      content = File.read(file)
      file if content.match?(/status\s*(\)|\.to_s)?\s*\.\s*(titleize|humanize)/)
    end
    expect(offenders).to be_empty,
      "lifecycle labels must render via lifecycle_status_label, never " \
      "status titleize/humanize (leaks 'Suspended'/'Discarded'): #{offenders.join(", ")}"
  end
end
