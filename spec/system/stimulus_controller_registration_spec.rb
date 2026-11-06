require "rails_helper"

# A controller works whether or not it is registered before the lazy loader,
# so no other assertion in the suite can see this — only the console (#1072).
RSpec.describe "Stimulus controller registration", type: :system do
  # A `let`, not a constant: a bare constant in a describe block lands on
  # Object and collides across parallel workers (#607).
  let(:console_capture_js) do
    <<~JS
      window.__consoleErrors = [];
      const originalConsoleError = console.error;
      console.error = (...args) => {
        try { window.__consoleErrors.push(args.map(String).join(" ")) } catch (_) {}
        originalConsoleError.apply(console, args);
      };
    JS
  end

  def console_errors
    page.evaluate_script("window.__consoleErrors || []")
  end

  # The failures fire during page load, so the patch is installed before it.
  # `visit` already waits for controllers to connect (spec/support/stimulus_ready.rb).
  before { cdp_add_init_script(console_capture_js) }

  it "logs no console error on the signed-out landing page" do
    visit new_session_path

    expect(console_errors).to be_empty
  end

  it "logs no console error on the docs index" do
    visit "/docs"

    expect(console_errors).to be_empty
  end
end
