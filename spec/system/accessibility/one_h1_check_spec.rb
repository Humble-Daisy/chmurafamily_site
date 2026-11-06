# frozen_string_literal: true

require "rails_helper"

# Harness self-test for the gate's mc-one-h1 check; it seeds broken headings, so app HTML is not under test.
RSpec.describe "axe gate one-h1 check", type: :system do
  def check_ids = run_axe_audit(exclude: []).fetch("violations").map { |v| v["id"] }

  it "fails an app page with a second <h1>" do
    visit new_session_path
    page.execute_script(%(document.querySelector("main").insertAdjacentHTML("beforeend", '<h1 id="h1-probe">Second</h1>')))

    expect(check_ids).to include("mc-one-h1")
  ensure
    page.execute_script('document.getElementById("h1-probe")?.remove()')
  end

  it "fails an app page whose only <h1> is not rendered" do
    visit new_session_path
    page.execute_script('document.querySelector("h1").style.display = "none"')

    expect(check_ids).to include("mc-one-h1")
  ensure
    page.execute_script('document.querySelector("h1").style.display = ""')
  end

  it "passes an app page with one <h1> and leaves component preview hosts alone" do
    visit new_session_path
    expect(check_ids).not_to include("mc-one-h1")

    visit "/rails/view_components/ui/kbd_component/default"
    expect(page).to have_no_css("h1")
    expect(check_ids).not_to include("mc-one-h1")
  end
end
