require "rails_helper"

# The failure MESSAGE names a violation that was gone by the time it ran (#1189).
RSpec.describe "Axe transient violation message", type: :system do
  # Planting ends with the block, so the teardown audit sees the real page.
  def planting(id, only_first: false)
    calls = 0
    active = true
    allow(self).to receive(:run_axe_audit).and_wrap_original do |original, *args, **kwargs|
      results = original.call(*args, **kwargs)
      calls += 1
      next results unless active
      next results if only_first && calls > 1

      results.merge(
        "violations" => [ {
          "id" => id,
          "help" => "planted for the message self-test",
          "impact" => "serious",
          "nodes" => []
        } ]
      )
    end
    yield
  ensure
    active = false
  end

  it "names the rule the check actually saw, even when it has already cleared" do
    visit new_session_path

    # only_first: the violation exists for the check and is gone by the message.
    planting("probe-transient", only_first: true) do
      expect {
        expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /probe-transient/)
    end
  end

  it "still reports a violation that is stable across audits" do
    visit new_session_path

    planting("probe-stable") do
      expect {
        expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /probe-stable/)
    end
  end

  # No extra audits on a green run (#855).
  it "adds no audits to a green run" do
    visit new_session_path
    ensure_light_mode
    baseline = axe_audit_run_count

    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    expect(axe_audit_run_count).to eq(baseline + 2),
      "a paired assertion should cost exactly two audits — one per theme"
  end
end
