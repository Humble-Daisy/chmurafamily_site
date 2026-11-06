require "rails_helper"

# Self-test for the per-example audit memo in spec/support/axe_accessibility.rb
# (#855): identical page state + options audit once per example; any DOM
# change, theme flip, or option change audits again. The memo is what makes
# the call sites' eagerly built failure message and the after-hook's end-state
# pass free when they re-audit exactly what the example already audited —
# without ever skipping an audit of state nothing has covered.
RSpec.describe "Axe audit memo", type: :system do
  it "audits once per page state and re-audits on any change" do
    visit new_session_path

    expect(axe_clean?).to be(true)
    baseline = axe_audit_run_count

    expect(axe_clean?).to be(true)
    expect(axe_audit_run_count).to eq(baseline)

    expect(axe_clean?(include: [ "main" ])).to be(true)
    expect(axe_audit_run_count).to eq(baseline + 1)

    page.execute_script("document.body.appendChild(document.createElement('p'))")
    expect(axe_clean?).to be(true)
    expect(axe_audit_run_count).to eq(baseline + 2)

    ensure_dark_mode
    expect(axe_clean?).to be(true)
    expect(axe_audit_run_count).to eq(baseline + 3)
  end

  it "never lets a memo hit mask a violation introduced after an audit" do
    visit new_session_path
    expect(axe_clean?).to be(true)

    # An <img> with no alt is a bread-and-butter axe failure.
    page.execute_script(<<~JS)
      const img = document.createElement("img");
      img.id = "memo-probe-img";
      img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACw=";
      document.body.appendChild(img);
    JS

    expect(axe_clean?).to be(false)

    page.execute_script("document.getElementById('memo-probe-img').remove()")
    expect(axe_clean?).to be(true)
  end
end
