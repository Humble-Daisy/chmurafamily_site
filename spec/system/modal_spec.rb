require "rails_helper"

RSpec.describe "Modal system", type: :system do
  before do
    visit new_session_path
    # Dismiss the cookie consent banner if present so it doesn't intercept pointer events
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
    # Set a fast animation duration on the root element (where the controller reads it from)
    page.execute_script("document.documentElement.style.setProperty('--modal-animation-duration', '50ms')")
  end

  def inject_test_modal(options = {})
    open_value = options[:open] ? 'data-modal-open-value="true"' : ""
    page.execute_script(<<~JS)
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'modal');
      #{options[:open] ? "wrapper.setAttribute('data-modal-open-value', 'true');" : ""}
      wrapper.innerHTML = `
        <button data-action="click->modal#open" id="test-modal-trigger" style="min-width:44px;min-height:44px">Open Modal</button>
        <dialog data-modal-target="dialog" id="test-modal"
                role="dialog" aria-modal="true" aria-labelledby="test-modal-title"
                class="bg-transparent backdrop:bg-transparent p-4">
          <div data-modal-target="panel"
               style="opacity:0; transform:scale(0.95); background:white; padding:24px; border-radius:8px; min-width:300px;">
            <h2 id="test-modal-title">Test Modal</h2>
            <p>Modal content for testing</p>
            <button data-action="click->modal#close" id="test-modal-close" aria-label="Close dialog" style="min-width:44px;min-height:44px">Close</button>
            <a href="#" id="test-modal-link" style="display:inline-flex;min-width:44px;min-height:44px;align-items:center">A focusable link</a>
          </div>
        </dialog>
      `;
      document.body.appendChild(wrapper);
    JS
  end

  describe "opening" do
    it "opens when trigger button is clicked" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end

    it "opens on connect when open value is true" do
      inject_test_modal(open: true)
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end
  end

  describe "closing" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "closes when close button is clicked" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on Escape key" do
      cdp_press("Escape")
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on backdrop click" do
      cdp_click_at(5, 5)
      expect(page).to have_no_css("dialog[open]")
    end

    it "returns focus to trigger button after close" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
      focused_id = page.evaluate_script("document.activeElement?.id")
      expect(focused_id).to eq("test-modal-trigger")
    end

    it "moves focus to the main region when the opener left the page while it was open" do
      page.execute_script("document.getElementById('test-modal-trigger').remove()")
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
      expect(page.evaluate_script("document.activeElement?.id")).to eq("main-content")
    end

    it "moves focus to the main region when the dialog is torn out of the page while open" do
      page.execute_script("document.getElementById('test-modal').closest('[data-controller~=\"modal\"]').remove()")
      expect(page).to have_no_css("#test-modal", visible: :all)
      expect(page.evaluate_script("document.activeElement?.id")).to eq("main-content")
    end
  end

  describe "accessibility" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "has role=dialog" do
      expect(page).to have_css("dialog[role='dialog']")
    end

    it "has aria-modal=true" do
      expect(page).to have_css("dialog[aria-modal='true']")
    end

    it "has aria-labelledby pointing to title" do
      expect(page).to have_css("dialog[aria-labelledby='test-modal-title']")
      expect(page).to have_css("h2#test-modal-title", text: "Test Modal")
    end

    it "close button is keyboard accessible" do
      # showModal() autofocuses the dialog's first focusable descendant (the
      # close button), so a raw Enter press exercises the native
      # focused-button activation path. Capybara's cross-driver `send_keys`
      # is NOT usable here: Cuprite's implementation performs a real mouse
      # click before typing (unlike Playwright's `press`), and that click
      # closes the dialog and restores focus to the trigger button BEFORE
      # the Enter keydown/keyup land — which then reopens the dialog via the
      # trigger's own native Enter-activates-focused-button behavior.
      find("#test-modal-close")
      cdp_press("Enter")
      expect(page).to have_no_css("dialog[open]")
    end
  end

  # #713. A dialog left open when the user navigates away can come back with the page:
  # Turbo's snapshot clone normalises only `select`, `input[type=password]` and
  # `noscript`, and the browser's back-forward cache normalises nothing at all. What
  # returns is a named dialog still carrying the hardcoded `aria-modal="true"`
  # (UI::DialogComponent), announced in DOM order, claiming the rest of the page is not
  # there, with Escape dead (`cancel` fires for modal dialogs only) and focus on <body>.
  #
  # There are two examples because there are two ways back to a page, and only one of
  # them is Turbo's. On a Drive visit Turbo defers `snapshot.clone()` one event-loop tick
  # past `turbo:before-cache`, so the clone is taken from the old body — and
  # `modal_controller#disconnect()` closes any open dialog on that body when Turbo
  # replaces it, so the app wins that one today. On a navigation Turbo does not render,
  # there is no snapshot at all: the browser keeps the live document and Back restores it
  # as it stood at unload. The sweep is what covers the second.
  describe "restore after leaving the page (#713)" do
    # The Drive case, where `disconnect()` happens to win the clone race. That is luck,
    # not design — see the example below for the route where nothing wins it for us —
    # and this one pins it so the incidental protection cannot be removed
    # silently. The closed dialog keeps its `aria-modal` attribute but is
    # `display: none`, so the assertion is deliberately visibility-scoped: nothing a
    # screen reader can reach may claim modality.
    it "restores with no open dialog and nothing exposed claiming modality" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      # A real Turbo link, clicked. `visit` is a hard browser goto: it fires no
      # `turbo:before-cache` and leaves the snapshot cache empty, so Back would
      # re-request the page and the restore under test never happens. The link goes
      # inside the panel because a modal dialog swallows every pointer event aimed
      # at the page behind it.
      page.execute_script(<<~JS)
        const link = document.createElement('a');
        link.id = 'test-modal-away';
        link.href = '/docs';
        link.textContent = 'Leave via Turbo';
        link.setAttribute('style', 'display:inline-flex;min-width:44px;min-height:44px;align-items:center');
        document.querySelector('[data-modal-target="panel"]').appendChild(link);
      JS
      click_link "Leave via Turbo"
      expect(page).to have_current_path("/docs")

      page.go_back

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_css("#test-modal", visible: :all)
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_no_css('[aria-modal="true"]')
    end

    # The case that does not go through Turbo's snapshot cache at all, and the one the
    # sweep actually earns its place on. Both stylesheet links carry
    # `data-turbo-track="reload"` (`shared/_layout_head.html.erb`), so stripping them
    # changes the tracked-element signature: `PageRenderer.shouldRender` is false, Turbo
    # invalidates with `reloadReason: "tracked_element_mismatch"`, and the destination is
    # fetched by a FULL browser load — Turbo renders nothing. Back is then served the
    # ORIGINAL document from the browser's back-forward cache, with its DOM exactly as it
    # stood at unload. `turbo:before-cache` has already fired by that point, so the sweep
    # is what makes that DOM correct; there is no snapshot for anything to fix later.
    # Measured: on the destination the original window's globals are gone (a real
    # navigation), and after Back they are back (the same document restored).
    #
    # Stripping is only how the test reaches an invalidating navigation cheaply. An
    # external link, `data-turbo="false"`, or a plain asset-digest change reaches the same
    # place in production, so this is a broader bug than a dialog surviving a Drive visit.
    #
    # Coupled to the bfcache being usable: `Cache-Control: no-store` on the root page
    # would make Back re-request instead of restoring, and the `#test-modal` assertion
    # below would fail for that reason rather than this one — the injected modal is
    # client-side only and no server response contains it.
    it "restores with no open dialog when the navigation away invalidates and Back uses bfcache" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      page.execute_script(<<~JS)
        const link = document.createElement('a');
        link.id = 'test-modal-away';
        link.href = '/docs';
        link.textContent = 'Leave via Turbo';
        link.setAttribute('style', 'display:inline-flex;min-width:44px;min-height:44px;align-items:center');
        document.querySelector('[data-modal-target="panel"]').appendChild(link);
      JS

      stripped = page.evaluate_script(<<~JS)
        (() => {
          const links = [...document.querySelectorAll('head link[rel="stylesheet"]')];
          links.forEach((l) => l.remove());
          return links.length;
        })()
      JS
      expect(stripped).to be_positive

      click_link "Leave via Turbo"
      expect(page).to have_current_path("/docs")

      page.go_back

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_css("#test-modal", visible: :all)
      expect(page).to have_no_css("dialog[open]")
      expect(page).to have_no_css('[aria-modal="true"]')

      # Land on a served page again. The teardown axe audit has no per-example opt-out
      # (by design, #912), and it would otherwise audit the stylesheet-less document
      # this example deliberately created — reporting target-size failures that are an
      # artifact of the setup, not of the UI.
      visit new_session_path
      expect(page).to have_css("head link[rel='stylesheet']", visible: :all)
    end
  end

  describe "reduced motion" do
    it "skips animation when prefers-reduced-motion is set" do
      cdp_emulate_reduced_motion
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      # Panel should be immediately visible (opacity 1, no transition)
      panel_opacity = page.evaluate_script(
        'document.querySelector("[data-modal-target=\\"panel\\"]")?.style.opacity'
      )
      expect(panel_opacity).to eq("1")
    end
  end
end
