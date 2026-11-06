# frozen_string_literal: true

require "rails_helper"

# Self-test for the teardown audit's always-on machinery (#912). The audit
# itself runs after every system example; what this file proves is the two
# things the after(:suite) gate in spec/support/axe_accessibility.rb relies
# on: the audit detects a planted violation, and the gate's bookkeeping sees
# an example that navigated. The gate's decision itself is a pure function,
# covered in spec/lib/axe_teardown_gate_spec.rb.
RSpec.describe "AAA teardown audit", type: :system do
  it "catches a planted violation in both themes, and is clean again once it is gone" do
    visit new_session_path
    expect(axe_violations_in_both_themes).to be_empty

    page.execute_script(<<~JS)
      const img = document.createElement("img");
      img.id = "axe-probe";
      img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACw=";
      document.body.appendChild(img);
    JS
    violations = axe_violations_in_both_themes
    expect(violations.grep(/image-alt/).size).to eq(2), violations.join("\n")

    page.execute_script("document.getElementById('axe-probe').remove()")
    expect(axe_violations_in_both_themes).to be_empty
  end

  it "records this example as having navigated, so the suite gate holds it to an audit" do
    visit new_session_path

    expect(AxeAccessibility::VISITED_EXAMPLES).to include(RSpec.current_example.id)
  end

  # Turbo marks whatever is busy with aria-busy="true": the document for a
  # visit, the form for a submission, a frame for a frame load. The teardown
  # audit waits all of it out rather than auditing mid-flight.
  it "waits for an in-flight Turbo visit to settle before auditing" do
    visit new_session_path
    page.execute_script(<<~JS)
      document.documentElement.setAttribute("aria-busy", "true");
      setTimeout(() => document.documentElement.removeAttribute("aria-busy"), 400);
    JS

    expect(wait_for_turbo_to_settle).to be(true)
    expect(page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")).to be(false)
  end

  it "waits for an in-flight form submission too, the state a redirect visit starts from" do
    visit new_session_path
    page.execute_script(<<~JS)
      const form = document.createElement("form");
      form.id = "axe-busy-form";
      form.setAttribute("aria-busy", "true");
      document.body.appendChild(form);
      setTimeout(() => form.removeAttribute("aria-busy"), 400);
    JS

    expect(wait_for_turbo_to_settle).to be(true)
    expect(page.evaluate_script("document.getElementById('axe-busy-form').hasAttribute('aria-busy')")).to be(false)
    page.execute_script("document.getElementById('axe-busy-form').remove()")
  end

  # The race this wait exists for, and the reason one check is not enough: a
  # frame swap that advances history goes quiet, and only THEN does Turbo start
  # the history visit and mark <html> busy again. Returning on the first quiet
  # moment handed axe a document mid-visit, which it reports as
  # aria-allowed-attr on <html>.
  it "keeps waiting when the page goes quiet and then busy again" do
    visit new_session_path
    page.execute_script(<<~JS)
      const html = document.documentElement;
      window.__busyCycles = 0;
      const busy = () => { window.__busyCycles += 1; html.setAttribute("aria-busy", "true"); };
      const idle = () => html.removeAttribute("aria-busy");
      busy();
      setTimeout(idle, 100);
      setTimeout(busy, 200);
      setTimeout(idle, 600);
    JS

    expect(wait_for_turbo_to_settle).to be(true)
    # Both busy periods are over, not only the first: a wait that returned at
    # the first quiet moment would see one.
    expect(page.evaluate_script("window.__busyCycles")).to eq(2)
    expect(page.evaluate_script("document.documentElement.hasAttribute('aria-busy')")).to be(false)
  end

  it "gives up on work that never settles and lets the audit report it" do
    visit new_session_path
    page.execute_script("document.documentElement.setAttribute('aria-busy', 'true')")

    expect(wait_for_turbo_to_settle(wait: 0.3)).to be(false)
    expect(axe_violations_in_both_themes.grep(/aria-allowed-attr/)).not_to be_empty

    page.execute_script("document.documentElement.removeAttribute('aria-busy')")
  end
end
