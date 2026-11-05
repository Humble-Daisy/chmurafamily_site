require "rails_helper"

# Self-test for the centralized Stimulus barrier in
# spec/support/stimulus_ready.rb. The gate was an allow-list of two paths
# (#525, #837), so 536 `visit` calls across 164 system spec files got no
# wait at all and raced controller boot on loaded shards. #837 asked for the
# gate to be widened rather than annotated call site by call site; these
# examples pin the three properties that makes safe: it covers ordinary app
# paths, it does not wait on a page that has no controllers to wait for, and
# it still fails loud instead of returning a silent false.
RSpec.describe "Stimulus readiness gate", type: :system do
  it "gates an ordinary app path, not just an allow-list" do
    expect(self).to receive(:wait_for_stimulus_controllers).at_least(:once).and_call_original

    visit new_session_path
  end

  it "leaves every controller on the page connected once visit returns" do
    visit new_session_path

    expect(all_stimulus_controllers_connected?).to be(true)
  end

  # A page with nothing to wait for must not spend the barrier's budget and
  # must not raise — otherwise widening the gate would turn every
  # controller-less page into a 2.5s timeout failure.
  it "treats a page with no controllers as ready" do
    visit new_session_path
    page.execute_script(
      "document.querySelectorAll('[data-controller]').forEach((e) => e.removeAttribute('data-controller'))"
    )

    expect(all_stimulus_controllers_connected?).to be(true)
    expect { wait_for_stimulus_controllers(attempts: 2, interval: 0.05) }.not_to raise_error
  end

  # The barrier's value is that an exhausted wait is distinguishable from a
  # satisfied one, and that the message names what never connected.
  it "raises and names the identifier when a controller never connects" do
    visit new_session_path
    page.execute_script(<<~JS)
      const el = document.createElement("div");
      el.setAttribute("data-controller", "never-going-to-connect");
      document.body.appendChild(el);
    JS

    expect { wait_for_stimulus_controllers(attempts: 3, interval: 0.05) }
      .to raise_error(/never-going-to-connect/)
  end
end
