require "rails_helper"

# Self-test for spec/support/csp_violation_capture.rb (#848): the listener must
# be listening in EVERY example, not just the first one a worker process runs.
# `Capybara.reset_sessions!` (rspec-rails' after-example system-test teardown) disposes the
# browser context and its page-scoped init script, so this spec replays that
# between-examples lifecycle mid-example and proves capture still works after.
RSpec.describe "CSP violation capture harness", type: :system do
  # An inline <script> without the session nonce: the enforced script-src
  # policy blocks it and the browser fires `securitypolicyviolation`.
  def trigger_deliberate_violation
    page.execute_script(<<~JS)
      const s = document.createElement("script");
      s.textContent = "window.__cspProbeRan = true";
      document.head.appendChild(s);
    JS
  end

  # `securitypolicyviolation` is dispatched as a queued task after the blocked
  # insertion, so poll briefly instead of reading once. Reads consume the list,
  # which also keeps the after-hook gate clean for this example.
  def violations_captured_within(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    violations = []
    loop do
      violations.concat(captured_csp_violations)
      return violations if violations.any? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  it "captures violations on the fresh page created after a session reset" do
    visit new_session_path
    trigger_deliberate_violation
    expect(violations_captured_within(2)).to include(a_string_matching(/script-src/))

    Capybara.reset_sessions!
    install_csp_violation_listener

    visit new_session_path
    trigger_deliberate_violation
    expect(violations_captured_within(2)).to include(a_string_matching(/script-src/))
  end
end
