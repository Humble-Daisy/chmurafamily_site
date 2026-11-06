require "rails_helper"

# Pins the best-practice tier decision (#464). axe's `best-practice` tag is not
# WCAG and is not a blocking tier — a sweep of the whole system suite on
# 2026-09-03 returned 1,782 findings, and 1,700 of them were `landmark-one-main`,
# `page-has-heading-one` and `region` on ViewComponent preview hosts and mail
# fragments, contexts whose page shape structurally cannot satisfy a page-shape
# rule. Three duplicate-landmark rules were the exception: in that same sweep
# they fired ONLY on real application pages, so they block.
#
# This spec is the fence in both directions. Without the "does not block" half,
# the obvious "fix" for a future preview-host finding is to widen the promoted
# list, which is exactly the burial the panel warned about.
RSpec.describe "Promoted best-practice axe rules", type: :system do
  before { visit new_session_path }

  it "blocks a duplicate main landmark" do
    expect(axe_clean?).to be(true)

    page.execute_script(<<~JS)
      const extra = document.createElement("main");
      extra.id = "promoted-probe-main";
      document.body.appendChild(extra);
    JS

    expect(axe_clean?).to be(false)

    page.execute_script("document.getElementById('promoted-probe-main').remove()")
    expect(axe_clean?).to be(true)
  end

  it "does not block an unpromoted best-practice rule" do
    expect(axe_clean?).to be(true)

    # page-has-heading-one fires on every preview host, so it stays advisory; red here means the list was widened.
    # A heading-less app page still fails the gate's own page-scoped mc-one-h1, which is not this rule.
    page.execute_script(<<~JS)
      document.querySelectorAll("h1").forEach(h => {
        const div = document.createElement("div");
        div.textContent = h.textContent;
        h.replaceWith(div);
      });
    JS

    expect(page).to have_no_css("h1", wait: 0)
    expect(run_axe_audit.fetch("violations").map { |v| v["id"] }).not_to include("page-has-heading-one")

    # Restore a real page for the teardown audit rather than leaving it a
    # heading-stripped mutant.
    visit new_session_path
  end
end
