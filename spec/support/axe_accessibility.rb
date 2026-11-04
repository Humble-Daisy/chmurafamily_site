# frozen_string_literal: true

# Accessibility testing helper using axe-core. Injects axe-core JavaScript and
# runs accessibility audits. Drives Chrome through the Ferrum/CDP helpers
# (CdpHelpers, `page.driver.browser`) — the pure-Ruby CDP path.
module AxeAccessibility
  AXE_SOURCE = Axe::Configuration.instance.jslib.freeze

  # Ledger for the teardown audit (#912). The after(:each) hook at the bottom
  # of this file writes one entry per system example: :audited, or :blank when
  # the example ended with no page. VisitTracking records which examples
  # navigated at all. `unaudited` reads the two against each other for the
  # after(:suite) gate: an example that navigated and was not audited is a
  # hole in the AAA invariant, whatever left the hole. The hook once sat inert
  # for months because a second `reset_sessions!` after-hook ran ahead of it
  # and it skipped every example as blank; this is what makes that loud.
  TEARDOWN_LEDGER = {}
  VISITED_EXAMPLES = Set.new

  def self.unaudited(example_ids, ledger: TEARDOWN_LEDGER, visited: VISITED_EXAMPLES)
    example_ids.reject do |id|
      ledger[id] == :audited || (ledger[id] == :blank && !visited.include?(id))
    end
  end

  # Prepended to system examples so the gate knows which ones navigated.
  # Covers the DSL `visit`; a bare `page.visit` is outside it, as it is for
  # StimulusReady.
  module VisitTracking
    def visit(*args, **kwargs)
      VISITED_EXAMPLES << RSpec.current_example.id if RSpec.current_example
      super
    end
  end

  # WCAG 2.2 AAA conformance is CUMULATIVE (2.0 + 2.1 + 2.2 at A/AA/AAA,
  # WCAG §5) — but axe tags each version separately (wcag2a ≠ wcag21a ≠
  # wcag22aa). Filtering on the 2.0-era tags alone silently skipped every
  # 2.1/2.2 rule on every audit (backlog #10, found via the Load-360 button).
  AXE_TAG_SET = %w[wcag2a wcag2aa wcag2aaa wcag21a wcag21aa wcag22aa].freeze

  # axe's `best-practice` tag is NOT a blocking tier, and #464 settled that it
  # never becomes one wholesale. A reporting sweep of the entire system suite
  # (2026-09-03, 169 spec files, both themes) returned 1,782 best-practice
  # findings; 1,700 of them were `landmark-one-main`, `page-has-heading-one`
  # and `region` on ViewComponent preview hosts and mail fragments — contexts
  # whose page shape structurally cannot satisfy a page-shape rule, which is
  # why the `include:` scoping doc above already treats them as out of scope.
  #
  # These three are the exception, and the reason a reporting-only tier was not
  # built: in that same sweep they fired ONLY on real application pages — never
  # once on a preview host or a mail fragment — and every finding was a genuine
  # duplicate-landmark defect (a nested <main> on /docs/*, a repeated landmark
  # name on /settings/notifications). A rule with no false-positive surface and
  # a 100% real-defect rate does not need an advisory lane to graduate from; it
  # needs to block.
  #
  # Widening this list is the failure mode to guard against — the panel's
  # original worry was burying the team in findings. Add a rule only with sweep
  # evidence that it too fires exclusively on real pages;
  # spec/system/accessibility/promoted_best_practice_rules_spec.rb fences both
  # directions.
  BEST_PRACTICE_TAG = "best-practice"
  PROMOTED_BEST_PRACTICE_RULES = %w[
    landmark-unique
    landmark-no-duplicate-main
    landmark-main-is-top-level
  ].freeze

  # Rules whose "incomplete" results fail like violations. A 2026-11-04 suite sweep found none of these deferred anywhere (#1549).
  PROMOTED_INCOMPLETE_RULES = %w[aria-hidden-focus].freeze

  # target-size (2.5.8 AA, 24px) ships `enabled: false` in axe 4.x — the tag
  # alone never runs it. The 44px AAA floor (2.5.5) has NO axe rule at all;
  # the mc-target-size-44 custom check below covers it.
  AXE_RULE_OVERRIDES = { "target-size" => { enabled: true } }.freeze

  DEFAULT_AXE_OPTIONS = {
    runOnly: { type: "tag", values: AXE_TAG_SET },
    rules: AXE_RULE_OVERRIDES
  }.freeze

  # `include` scopes the audit to one or more DOM subtrees (axe `context`
  # selectors). Use it to audit a single COMPONENT rather than the whole page —
  # e.g. a preview-host page whose minimal layout emits `best-practice`
  # advisories (landmark-one-main, page-has-heading-one) that are not WCAG and
  # not about the component under test. Scoping to the component keeps those
  # host-chrome advisories out of scope WITHOUT excluding any rule. Do NOT use
  # it to scope a real color-contrast failure out of the audit.
  #
  # Color-contrast violations are enriched with a `_debug` payload (ancestor
  # chain computed styles, theme state, in-flight animations) so failure
  # messages reveal the cascade reality at scan time. See §2b flake
  # investigation for the motivating case.
  def run_axe_audit(options = {}, exclude: [], include: nil)
    # A caller's runOnly tags are ADDED to the cumulative set, never swapped
    # for it (#829). `||=` meant a caller-supplied value replaced AXE_TAG_SET
    # outright, so the 32 system specs passing ["wcag2aaa"] audited the three
    # AAA-tagged rules and skipped the entire A/AA foundation — labels, alt
    # text, accessible names, document titles — while the harness self-test
    # stayed green, because it exercises the default path these callers
    # bypass. Narrowing coverage must not be something a caller can do by
    # accident; adding a tag is.
    options = options.symbolize_keys
    # BEST_PRACTICE_TAG rides along so the promoted rules RUN; axe has no way
    # to say "these tags plus these three rules", and everything the tag brings
    # that is not promoted is dropped from the results below. Keep the two
    # halves together: adding the tag without the filter turns every
    # preview-host page-shape advisory into a blocking failure.
    options[:runOnly] = {
      type: "tag",
      values: (AXE_TAG_SET | [ BEST_PRACTICE_TAG ] | Array(options.dig(:runOnly, :values))).freeze
    }
    options[:rules] = AXE_RULE_OVERRIDES.merge(options[:rules] || {})

    exclude_list = Array(exclude)
    include_list = Array(include)

    # Per-example memo (#855): the same page state audited with the same
    # normalized options returns the cached result. Before this, a
    # `axe_clean_in_both_themes?` call site paid SIX audits — two for the
    # check, two for the eagerly evaluated failure-message argument, and two
    # in the after-hook — all on identical state. Keyed on a DOM fingerprint
    # (so a theme flip, toast style mutation, or any markup change is a miss)
    # plus the full option set (so a component-scoped audit can never satisfy
    # the hook's full-page pass). Misses only ever run a real audit — the
    # unsafe direction does not exist. spec/system/axe_audit_memo_spec.rb
    # pins both properties.
    memo_key = [ axe_page_fingerprint, options, exclude_list, include_list ]
    @__axe_audit_memo ||= {}
    return @__axe_audit_memo[memo_key] if @__axe_audit_memo.key?(memo_key)

    inject_axe

    # Ferrum's evaluate_async appends a resolve callback as the LAST argument of
    # the wrapping function; the async IIFE reaches it via
    # `arguments[arguments.length - 1]` (arrow functions inherit the enclosing
    # function's `arguments`). We resolve `JSON.stringify(results)` — a single
    # string round-trip that mirrors Playwright's returnByValue JSON semantics —
    # then JSON.parse below. Resolving the raw object instead would route through
    # Ferrum's handle_response/reduce_props, a recursive CDP getProperties walk
    # per nested object (thousands of round-trips over the full axe result) that
    # also `.compact`s arrays. The try/catch guarantees resolve is always called
    # so an in-IIFE throw surfaces as a raised error instead of a 20s timeout.
    raw = cdp_evaluate_async(<<~JAVASCRIPT)
        (async () => {
          try {
          const options = #{options.to_json};
          const exclude = #{exclude_list.to_json};
          const include = #{include_list.to_json};
          const context = {};
          if (include.length > 0) context.include = include;
          if (exclude.length > 0) context.exclude = exclude;

          // Settle in-flight CSS transitions/animations before auditing so
          // color-contrast is computed on the FINAL painted state, not a
          // mid-transition composite. A dialog caught mid-open at ~0.67 opacity
          // blends its (settled-AAA) background over the surface below it, and
          // axe reports a bogus sub-threshold ratio — the §2b surface-drift
          // flake (~1-in-3 under full-suite load, when the open animation is
          // still running as the sweep fires). finish() jumps each FINITE
          // animation to its end state; infinite animations (spinners) throw
          // InvalidStateError and are skipped, so this can't hang the audit.
          document.getAnimations().forEach((a) => { try { a.finish(); } catch (_) {} });
          void document.body.offsetHeight; // force reflow so computed styles reflect the settled state

          const results = (context.include || context.exclude)
            ? await axe.run(context, options)
            : await axe.run(options);

          const findNode = (target) => {
            try { return document.querySelector(target[target.length - 1]); }
            catch (_) { return null; }
          };

          const captureAncestors = (el) => {
            const chain = [];
            let current = el;
            while (current && current !== document.documentElement) {
              const cs = getComputedStyle(current);
              const transition = cs.transition && cs.transition !== "all 0s ease 0s" ? cs.transition : "none";
              chain.push({
                tag: current.tagName,
                classes: Array.from(current.classList).join(" "),
                backgroundColor: cs.backgroundColor,
                opacity: cs.opacity,
                transition: transition
              });
              current = current.parentElement;
            }
            return chain;
          };

          const captureAnimations = () => {
            try {
              return document.getAnimations().map(a => ({
                type: a.constructor.name,
                currentTime: a.currentTime,
                effectTargetTag: a.effect && a.effect.target ? a.effect.target.tagName : null,
                effectTargetClass: a.effect && a.effect.target ? a.effect.target.className : null
              }));
            } catch (_) { return []; }
          };

          const captureTheme = () => ({
            htmlClasses: Array.from(document.documentElement.classList).join(" "),
            cookieTheme: (document.cookie.match(/theme=(\\w+)/) || [])[1] || null
          });

          for (const v of (results.violations || [])) {
            if (!v.id || !v.id.includes("color-contrast")) continue;
            for (const node of (v.nodes || [])) {
              const el = findNode(node.target || []);
              node._debug = {
                ancestorChain: el ? captureAncestors(el) : [],
                theme: captureTheme(),
                animations: captureAnimations(),
                timestamp: Date.now(),
                elementFound: !!el
              };
            }
          }

          // ------- backlog #10: checks axe cannot perform -------
          const INTERACTIVE = 'a[href], button, input:not([type=hidden]), select, textarea, summary, [tabindex]:not([tabindex="-1"]), [role="button"], [role="link"]';
          const excludedEl = (el) => exclude.some(sel => { try { return el.closest(sel); } catch (_) { return false; } });
          const inScope = (el) => include.length === 0 || include.some(sel => { try { return el.closest(sel); } catch (_) { return false; } });
          const visibleEl = (el) => {
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && cs.visibility !== "hidden" && cs.display !== "none";
          };
          const describe = (el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
            (el.classList.length ? "." + [...el.classList].slice(0, 3).join(".") : "");
          const pushCheck = (id, help, nodes) => {
            if (nodes.length) results.violations.push({ id, help, impact: "serious",
              nodes: nodes.map(n => ({ html: n.el.outerHTML.slice(0, 160), target: [describe(n.el)], failureSummary: n.why })) });
          };
          const focusables = [...document.querySelectorAll(INTERACTIVE)]
            .filter(el => visibleEl(el) && !excludedEl(el) && inScope(el) && !el.disabled);

          const alphaOf = (color) => {
            if (!color || color === "transparent") return 0;
            const slash = color.match(/\\/\\s*([\\d.]+%?)\\s*\\)/);
            if (slash) return slash[1].endsWith("%") ? parseFloat(slash[1]) / 100 : parseFloat(slash[1]);
            const rgba = color.match(/rgba\\(([^)]+)\\)/);
            if (rgba) { const parts = rgba[1].split(","); return parts.length === 4 ? parseFloat(parts[3]) : 1; }
            return 1;
          };
          const hasOpaquePlate = (el) => {
            let cur = el;
            while (cur && cur !== document.documentElement) {
              if (alphaOf(getComputedStyle(cur).backgroundColor) >= 0.9) return true;
              cur = cur.parentElement;
            }
            return false;
          };

          // axe files can't-compute contrast under `incomplete` for many
          // benign reasons (an <img> INSIDE a button, partial overlaps). The
          // defect class is an interactive element with NO opaque plate
          // anywhere up-chain — contrast genuinely unguaranteed. Elements on
          // a solid ancestor are axe's limitation, not a design bug.
          for (const v of (results.incomplete || [])) {
            if (!v.id || !v.id.includes("color-contrast")) continue;
            const nodes = (v.nodes || []).filter(n => {
              const el = findNode(n.target || []);
              return el && el.closest(INTERACTIVE) && !excludedEl(el) && inScope(el) &&
                     !hasOpaquePlate(el.closest(INTERACTIVE));
            });
            if (nodes.length) results.violations.push({
              id: v.id + "-incomplete-interactive", impact: "serious", nodes,
              help: "axe could not compute contrast for an interactive element with no opaque background plate up-chain"
            });
          }

          // WCAG 2.5.5 (AAA): 44x44 minimum target. The label union counts —
          // a 20px checkbox inside a 44px-tall labelled row passes, matching
          // how the SC measures the effective target.
          const tooSmall = [];
          for (const el of focusables) {
            const cs = getComputedStyle(el);
            if (cs.display === "inline" && el.matches("a[href]")) continue; // in-text link exception
            // sr-only bypass LINKS (skip-to-content) are clipped to ~1px while
            // blurred BY DESIGN and expand on focus — measuring the blurred
            // rect is a false positive. a[href] ONLY (#742): a visually-hidden
            // <input> behind a styled control (toggle, custom checkbox) must
            // NOT ride this exemption — its real target is the wrapping
            // label, and the label-union measurement below is exactly what
            // holds that to the 44px floor.
            const blurredRect = el.getBoundingClientRect();
            if (blurredRect.width <= 2 && blurredRect.height <= 2 && cs.position === "absolute" && el.matches("a[href]")) continue;
            // Composite-widget interiors (panel call, 2026-07-13): menu and
            // listbox items keep desktop density — 2.5.5 is NOT CLAIMED for
            // them on fine pointers (documented conformance deviation). They
            // are still held to the 24px 2.5.8 AA floor here, and a
            // pointer:coarse rule bumps them to 44px on touch devices, the
            // population the SC protects.
            const widgetItem = el.matches("[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=option]") &&
                               el.closest("[role=menu],[role=menubar],[role=listbox]");
            const floor = widgetItem ? 23.5 : 43.5;
            // Every visible label is a candidate target of its own (#912). A
            // label that wraps the control or sits within the field's own
            // label-to-control spacing unions with it — that is the labelled
            // field the SC measures. FIELD_GAP is FormFieldComponent's `mt-3`
            // (12px) plus 2px of sub-pixel slack for rounded rects. A
            // label elsewhere on the page counts by its own box: the space
            // between two separate regions is not a target, so unioning
            // them made a phantom rectangle that passed a 1px control by
            // spanning the page. Hidden labels (display:none,
            // visibility:hidden, empty box) are not candidates at all.
            const FIELD_GAP = 14;
            const unions = [ blurredRect ];
            for (const label of (el.labels || [])) {
              if (!visibleEl(label)) continue;
              const lr = label.getBoundingClientRect();
              const touches = !(lr.right < blurredRect.left - FIELD_GAP || lr.left > blurredRect.right + FIELD_GAP ||
                                lr.bottom < blurredRect.top - FIELD_GAP || lr.top > blurredRect.bottom + FIELD_GAP);
              unions.push(touches
                ? { width: Math.max(blurredRect.right, lr.right) - Math.min(blurredRect.left, lr.left),
                    height: Math.max(blurredRect.bottom, lr.bottom) - Math.min(blurredRect.top, lr.top) }
                : { width: lr.width, height: lr.height });
            }
            // Layout-box fallback: getBoundingClientRect shrinks under
            // transforms — an audit racing a dialog's 200ms close animation
            // (panel at scale .95) measured 44px buttons at 42. offsetWidth/
            // Height ignore transforms; persistent scale bugs are prevented
            // at the source (no scale-* rest classes on panels).
            const boxes = unions.map(u => ({ w: Math.max(u.width, el.offsetWidth || 0), h: Math.max(u.height, el.offsetHeight || 0) }));
            const { w, h } = boxes.reduce((a, b) => Math.min(b.w, b.h) > Math.min(a.w, a.h) ? b : a);
            if (w < floor || h < floor)
              tooSmall.push({ el, why: `target ${Math.round(w)}x${Math.round(h)} — floor is ${widgetItem ? "24x24 (2.5.8 AA, widget-item deviation)" : "44x44 (2.5.5)"}` });
          }
          pushCheck("mc-target-size-44", "Touch targets must be at least 44x44 (WCAG 2.5.5 AAA; label union counts)", tooSmall);

          // A control whose composited background never reaches ~opacity over
          // media has UNKNOWABLE contrast (the Load-360 defect class). True
          // PAINT-STACK test at the control's center (rect intersection
          // false-positived on controls merely sharing a box with a sibling
          // thumbnail): walking elementsFromPoint top-down, the control (or
          // one of its descendants — a plated chip inside a tabbable tooltip
          // wrapper) with an opaque background means plated; hitting media
          // before ANY opaque background means unguaranteed contrast.
          // "Media" for contrast purposes is not only <img>/<canvas>/<video>:
          // an inline <svg>, or a photo set via CSS `background-image: url()`,
          // is just as unknowable a backdrop (2026-07-13 review). A gradient/
          // solid background-image is NOT treated as media (not a raster), but
          // its opacity is also not asserted — an opaque background-color plate
          // is still required.
          const isMedia = (node) => {
            if (node.matches && node.matches("img, canvas, video, svg")) return true;
            const bg = getComputedStyle(node).backgroundImage;
            return typeof bg === "string" && bg.includes("url(");
          };
          // Returns the offending media node (not a boolean) so the report can
          // name what overlapped the control: a CI-only occurrence on the
          // workspace heading link could not be diagnosed from the control alone.
          const mediaUnderControl = (el) => {
            const r = el.getBoundingClientRect();
            const stack = document.elementsFromPoint(r.left + r.width / 2, r.top + r.height / 2);
            if (!stack.includes(el)) return null; // center not on the control (covered/offscreen)
            for (const node of stack) {
              const opaque = alphaOf(getComputedStyle(node).backgroundColor) >= 0.9;
              if (node === el || el.contains(node)) {
                if (opaque) return null;
                continue;
              }
              if (opaque) return null;
              if (isMedia(node)) return node;
            }
            return null;
          };
          const seeThrough = focusables
            .map(el => ({ el, media: mediaUnderControl(el) }))
            .filter(({ media }) => media)
            .map(({ el, media }) => {
              const mr = media.getBoundingClientRect();
              const cr = el.getBoundingClientRect();
              return { el, why: `transparent control overlapping media — contrast is unknowable; add an opaque plate. Media under the control's centre: ${describe(media)} at ${Math.round(mr.left)},${Math.round(mr.top)} ${Math.round(mr.width)}x${Math.round(mr.height)}; control at ${Math.round(cr.left)},${Math.round(cr.top)} ${Math.round(cr.width)}x${Math.round(cr.height)}` };
            });
          pushCheck("mc-transparent-over-media", "Interactive elements over images/canvas/video need an opaque background", seeThrough);

          // WCAG 2.4.7 — deterministic CSSOM analysis, not focus mutation:
          // Chromium does not reliably honor focus({focusVisible:true}) after
          // pointer input, which made a diff-the-styles version flaky. An
          // element passes when an author :focus/:focus-visible/:focus-within
          // rule with paint-affecting declarations matches it, OR when no
          // author rule suppresses the outline (the UA default ring shows).
          const focusSelectors = [];
          const suppressSelectors = [];
          const PAINTS = ["outline-style", "outline-width", "outline", "box-shadow", "background-color", "border-color", "text-decoration-line", "color"];
          const collectRules = (rules) => { for (const rule of rules) { try {
            if (rule.cssRules && rule.cssRules.length) collectRules(rule.cssRules);
            const sel = rule.selectorText;
            if (!sel || !rule.style) continue;
            if (/:focus/.test(sel)) {
              if (!PAINTS.some(p => rule.style.getPropertyValue(p))) continue;
              for (const part of sel.split(",")) {
                if (!/:focus/.test(part)) continue;
                const stripped = part.replace(/:focus-visible|:focus-within|:focus/g, "").trim();
                if (stripped) focusSelectors.push(stripped);
              }
            } else if (["none", "0px"].includes(rule.style.getPropertyValue("outline-style") || rule.style.getPropertyValue("outline-width")) ||
                       rule.style.getPropertyValue("outline") === "0") {
              // Strip :focus* SYMMETRICALLY with the focus branch above — a
              // suppressor like `.btn:focus-visible { outline: none }` must
              // reduce to `.btn` to match during this UNFOCUSED sweep (keeping
              // the pseudo made el.matches() always false, silently missing
              // the most common way focus rings are killed; 2026-07-13 review).
              for (const part of sel.split(",")) {
                const stripped = part.replace(/:focus-visible|:focus-within|:focus/g, "").trim();
                if (stripped) suppressSelectors.push(stripped);
              }
            }
          } catch (_) {} } };
          for (const s of document.styleSheets) { try { collectRules(s.cssRules); } catch (_) {} }
          const matchesAny = (el, sels) => sels.some(sel => { try { return el.matches(sel); } catch (_) { return false; } });
          // The indicator may live on a WRAPPER via :focus-within (e.g. a
          // search box whose ring is on the bordered container) — walk up.
          const anyAncestorFocusStyle = (el) => {
            for (let a = el; a && a !== document.body; a = a.parentElement) {
              if (matchesAny(a, focusSelectors)) return true;
            }
            return false;
          };
          const noIndicator = focusables
            .filter(el => matchesAny(el, suppressSelectors) && !anyAncestorFocusStyle(el))
            .map(el => ({ el, why: "outline suppressed by author CSS with no :focus/:focus-visible paint rule matching this element or an ancestor (WCAG 2.4.7)" }));
          pushCheck("mc-focus-indicator", "Focusable elements must show a visible focus indicator (WCAG 2.4.7)", noIndicator);

          // A visually hidden focusable (sr-only: a 1px clipped box) keeps
          // the UA outline, so the sweep above passes it while a keyboard
          // user sees nothing (#947; the identity picker's file input was
          // this). Such a control passes only if something VISIBLE paints on
          // its focus. Rather than parse selector text (Tailwind's escaped
          // class names contain the literal text ":focus-visible", which
          // defeats any regex), the control is given a probe class and every
          // focus rule is re-evaluated with its :focus* pseudo replaced by
          // that class (:focus-within becomes :has(.probe)): whichever
          // element then matches is what would paint on the control's focus.
          // Covers `input:focus + label`, `.peer:focus-visible ~ .track`,
          // `label:has(+ input:focus-visible)`, and `has-[:focus-visible]:`
          // utilities alike. Bypass links stay exempt: they expand themselves
          // on focus, which paints nothing PAINTS lists.
          const PROBE = "__axe-focus-probe";
          const UNESCAPED_FOCUS = /(?<!\\\\):focus/;
          const focusRuleParts = [];
          const collectFocusParts = (rules) => { for (const rule of rules) { try {
            if (rule.cssRules && rule.cssRules.length) collectFocusParts(rule.cssRules);
            const sel = rule.selectorText;
            if (!sel || !rule.style || !UNESCAPED_FOCUS.test(sel)) continue;
            if (!PAINTS.some(p => rule.style.getPropertyValue(p))) continue;
            for (const part of sel.split(",")) if (UNESCAPED_FOCUS.test(part)) focusRuleParts.push(part.trim());
          } catch (_) {} } };
          for (const s of document.styleSheets) { try { collectFocusParts(s.cssRules); } catch (_) {} }
          const paintsSomewhereVisible = (el) => {
            el.classList.add(PROBE);
            try {
              return focusRuleParts.some(part => {
                const probed = part
                  .replace(/(?<!\\\\):focus-within/g, `:has(.${PROBE})`)
                  .replace(/(?<!\\\\):focus-visible|(?<!\\\\):focus/g, `.${PROBE}`);
                try { return [...document.querySelectorAll(probed)].some(node => node !== el && visibleEl(node)); }
                catch (_) { return false; }
              });
            } finally { el.classList.remove(PROBE); }
          };
          const hiddenUnpainted = focusables.filter(el => {
            const r = el.getBoundingClientRect();
            if (r.width > 2 || r.height > 2) return false;
            if (el.matches("a[href]") && getComputedStyle(el).position === "absolute") return false; // bypass link
            return !paintsSomewhereVisible(el);
          }).map(el => ({ el, why: "focus lands on a hidden box and nothing visible paints on its focus: add a :focus-visible rule on its label, an ancestor, or a counterpart via :has()/sibling (WCAG 2.4.7)" }));
          pushCheck("mc-focus-indicator-hidden", "Visually hidden focusables need a visible element that paints on their focus (WCAG 2.4.7)", hiddenUnpainted);

          arguments[arguments.length - 1](JSON.stringify(results));
          } catch (__axeErr) {
            arguments[arguments.length - 1](JSON.stringify({
              __axe_error: (__axeErr && __axeErr.message) || String(__axeErr),
              __axe_stack: __axeErr && __axeErr.stack
            }));
          }
        })();
      JAVASCRIPT

    result = JSON.parse(raw)
    if result.is_a?(Hash) && result["__axe_error"]
      raise "axe-core audit failed in the browser: #{result["__axe_error"]}\n#{result["__axe_stack"]}"
    end

    # Drop what BEST_PRACTICE_TAG dragged in beyond the promoted rules. A
    # violation survives if it carries any WCAG tag (the real gate) or is one
    # of the three promoted rules. The custom mc-* checks pushed by the JS above
    # carry no tags at all and are matched by neither clause, so they are named
    # explicitly rather than surviving by accident.
    promoted = Array(result["incomplete"]).select { |v| PROMOTED_INCOMPLETE_RULES.include?(v["id"]) }
    result["violations"] = (Array(result["violations"]) + promoted).select do |v|
      (Array(v["tags"]) & AXE_TAG_SET).any? ||
        PROMOTED_BEST_PRACTICE_RULES.include?(v["id"]) ||
        v["id"].to_s.start_with?("mc-")
    end

    @__axe_audit_run_count = axe_audit_run_count + 1
    @__axe_audit_memo[memo_key] = result
  end

  # Turbo work still in flight at teardown is not a page state. Turbo marks
  # whatever is busy with aria-busy="true": <html> for a visit, the <form>
  # for a submission, a <turbo-frame> for a frame load (turbo-rails 8.0.23,
  # turbo.js markAsBusy at 227, called at 993, 4384, 4787, 4808). axe reports
  # the attribute on <html> as an ARIA error (#948, two CI shards). A form
  # submission whose redirect visit has not started yet shows only on the
  # form, which is why the wait covers every busy element and not just the
  # document. Waits for all of it to clear so the audit sees the page the
  # user lands on; false if it never did within the budget, in which case
  # the audit runs anyway and its report says why.
  # One quiet moment is not a settled page: a frame swap that advances history
  # clears aria-busy, and only then does Turbo start the history visit and mark
  # <html> busy again. So each time the page goes quiet, look again after
  # QUIET_FOR and only believe it if it is still quiet.
  QUIET_FOR = 0.15

  def wait_for_turbo_to_settle(wait: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait

    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return false if remaining <= 0
      return false unless page.has_no_css?("[aria-busy='true']", wait: remaining)

      sleep QUIET_FOR
      return true if page.has_no_css?("[aria-busy='true']", wait: 0)
    end
  end

  # Real (non-memoized) audits this example has run — the observability handle
  # for axe_audit_memo_spec.
  def axe_audit_run_count
    @__axe_audit_run_count ||= 0
  end

  # Cheap in-browser rolling hash of the document, plus the focused element
  # and URL — anything axe could see differently changes it. An unqueryable
  # page returns a never-equal key, so the fallback direction is always a
  # fresh audit, never a stale reuse.
  def axe_page_fingerprint
    digest = page.evaluate_script(<<~JS)
      (() => {
        const s = document.documentElement.outerHTML;
        let h = 0;
        for (let i = 0; i < s.length; i++) { h = (Math.imul(h, 31) + s.charCodeAt(i)) | 0; }
        const ae = document.activeElement;
        return h + ":" + (ae ? ae.tagName + "#" + (ae.id || "") : "none");
      })()
    JS
    [ page.current_url, digest ]
  rescue StandardError
    Object.new
  end

  # Stores the violations so the paired message reports this audit (#1189).
  def axe_clean?(options = {}, exclude: [], include: nil)
    violations = axe_violations_now(options, exclude: exclude, include: include)
    (@__axe_seen_violations ||= {})[axe_capture_key(options, exclude, include)] = violations
    violations.empty?
  end

  # Color-contrast violations include the ancestor-chain / theme / animation
  # debug payload captured by `run_axe_audit`.
  def axe_violations(options = {}, exclude: [], include: nil)
    key = axe_capture_key(options, exclude, include)
    seen = (@__axe_seen_violations ||= {})
    return seen[key] if seen.key?(key)

    axe_violations_now(options, exclude: exclude, include: include)
  end

  # Always audits. The capturing wrappers above and below decide when to reuse.
  def axe_violations_now(options, exclude:, include:)
    results = run_axe_audit(options, exclude: exclude, include: include)
    Array(results["violations"]).map { |v| format_violation(v) }
  end

  # Keyed on arguments: each message twin receives its check's exact arguments.
  def axe_capture_key(options, exclude, include)
    [ options, exclude, include ]
  end

  # Color-contrast violations surface the diagnostic payload (`_debug` on each
  # node) so the cascade and theme state at scan time are visible in CI logs.
  def format_violation(violation)
    id     = violation["id"].to_s
    help   = violation["help"]
    impact = violation["impact"]
    nodes  = Array(violation["nodes"])

    lines = []
    lines << "\n#{id}: #{help}"
    lines << "  Impact: #{impact}"
    lines << "  Affected elements:"

    nodes.each do |node|
      lines << "  #{node["html"]}"
      summary = node["failureSummary"].to_s
      lines << "      #{summary.gsub("\n", "\n      ")}" unless summary.empty?
      next unless id.include?("color-contrast")

      debug = node["_debug"]
      if debug.nil?
        lines << "    (no diagnostic payload captured)"
        next
      end

      lines << "    Ancestor chain:"
      Array(debug["ancestorChain"]).each_with_index do |a, i|
        indent  = "      " + ("  " * i)
        tag     = a["tag"]
        classes = a["classes"].to_s.empty? ? "" : ".#{a["classes"]}"
        lines << "#{indent}#{tag}#{classes}  bg=#{a["backgroundColor"]}  opacity=#{a["opacity"]}  transition=#{a["transition"]}"
      end

      theme = debug["theme"] || {}
      lines << "    Theme: html=#{theme["htmlClasses"].inspect} cookie=#{theme["cookieTheme"].inspect}"

      animations = Array(debug["animations"])
      if animations.empty?
        lines << "    Animations: none"
      else
        lines << "    Animations:"
        animations.each do |a|
          lines << "      #{a["type"]} target=#{a["effectTargetTag"] || "?"} class=#{a["effectTargetClass"].inspect} t=#{a["currentTime"]}"
        end
      end
    end

    lines.join("\n")
  end

  def axe_clean_in_both_themes?(options = {}, exclude: [], include: nil)
    ensure_light_mode
    light = axe_violations_now(options, exclude: exclude, include: include).map { |v| "[LIGHT]#{v}" }
    ensure_dark_mode
    dark = axe_violations_now(options, exclude: exclude, include: include).map { |v| "[DARK]#{v}" }

    (@__axe_seen_both_themes ||= {})[axe_capture_key(options, exclude, include)] = light + dark
    (light + dark).empty?
  end

  # Combined violations from both light and dark mode passes, prefixed with the
  # active theme so failure output makes the offending mode obvious.
  def axe_violations_in_both_themes(options = {}, exclude: [], include: nil)
    key = axe_capture_key(options, exclude, include)
    seen = (@__axe_seen_both_themes ||= {})
    return seen[key] if seen.key?(key)

    ensure_light_mode
    light = axe_violations(options, exclude: exclude, include: include).map { |v| "[LIGHT]#{v}" }
    ensure_dark_mode
    dark = axe_violations(options, exclude: exclude, include: include).map { |v| "[DARK]#{v}" }
    light + dark
  end

  def expect_aaa_in_both_themes(options = {}, include: nil)
    expect(axe_clean_in_both_themes?(options, include: include)).to(
      be(true),
      axe_violations_in_both_themes(options, include: include).join("\n")
    )
  end

  # Force the document into light mode by setting the theme controller's value
  # and removing the .dark class. Mirrors what the theme-toggle controller does
  # when the user picks "light" but bypasses the cycle/click ergonomics so it
  # works the same regardless of starting state or cookie value.
  def ensure_light_mode
    set_theme("light")
  end

  def ensure_dark_mode
    set_theme("dark")
  end

  private

  def set_theme(theme)
    # Async: it AWAITS the color transitions, so it must run through
    # cdp_evaluate_async (which awaits the Promise) and resolve the ferrum
    # callback when done. The try/catch resolves `true` even on an unexpected
    # throw so a post-await failure can never hang for the full 20s wait.
    cdp_evaluate_async(<<~JS)
        (async () => {
          try {
          const html = document.documentElement;
          html.dataset.themeThemeValue = #{theme.to_json};
          html.classList.toggle("dark", #{(theme == "dark").to_json});
          document.cookie = "theme=#{theme};path=/;max-age=31536000;SameSite=Lax";
          // Force reflow so the cascade recomputes.
          document.body.offsetHeight;
          // The flip triggers `transition-colors` on many elements (150ms).
          // Axe samples computed styles, so without awaiting these transitions
          // we capture mid-flight interpolations and get phantom AAA failures
          // (the §2b "surface drift" symptom). Filter to CSSTransition so we
          // never wait on infinite CSSAnimations (e.g. animate-spin). 500ms
          // cap is defense-in-depth against runaway transitions.
          const transitions = document.getAnimations().filter(a => a instanceof CSSTransition);
          await Promise.race([
            Promise.allSettled(transitions.map(t => t.finished)),
            new Promise(r => setTimeout(r, 500))
          ]);
          arguments[arguments.length - 1](true);
          } catch (__themeErr) {
            arguments[arguments.length - 1](true);
          }
        })();
      JS
  end

  def inject_axe
    return if cdp_evaluate("typeof window.axe !== 'undefined'")

    # `execute` (raw statement, no implicit `return`) — NOT `evaluate`, which
    # wraps in `function(){ return … }` and breaks axe-core's UMD self-assign
    # to `window`.
    cdp_execute(AXE_SOURCE)
  end
end

RSpec.configure do |config|
  config.include AxeAccessibility, type: :system

  # Automatically audit every system spec, everywhere — not just CI.
  #
  # This was `if ENV["CI"]` until #541. Gating it meant a developer got no
  # accessibility feedback at all until they pushed, so every finding cost a
  # full CI cycle to discover and another to fix — and a real AAA violation
  # (#540) sat on main precisely because nobody ran the audit locally.
  # Accessibility is a project invariant at WCAG 2.2 AAA; an invariant you only
  # check on someone else's machine isn't one.
  #
  # SKIP_AXE=1 opts out for a fast focused loop. It is deliberately opt-OUT:
  # the default has to be the safe one, or this regresses to CI-only by habit.
  unless ENV["SKIP_AXE"] == "1"
    config.after(:each, type: :system) do |example|
      # No page, nothing to audit: an example that never navigated (a
      # request-level check under type: :system, or one that failed in setup).
      # An example that DID navigate and still ends here is #912 — something
      # disposed the session before this hook — and the after(:suite) gate
      # below fails the run for it. There is no per-example opt-out: a page a
      # preview must render deliberately wrong is fixed to be right instead.
      # Only a truly empty document is skipped: an about:blank whose body was
      # written by the example (a mail template loaded for audit, #461) is a
      # page state like any other.
      if Capybara.current_session.current_url.start_with?("about:") &&
         !Capybara.current_session.evaluate_script("!!(document.body && document.body.children.length)")
        AxeAccessibility::TEARDOWN_LEDGER[example.id] = :blank
        next
      end

      wait_for_turbo_to_settle
      # Prepare toasts for audit:
      # - Defeat in-progress animations (element opacity, transforms)
      # - Force a solid background so axe can reliably compute color contrast.
      #   The toast's production background uses alpha transparency (oklch / 90%),
      #   which requires axe to walk up the DOM and blend with ancestors. That
      #   walk-up is sensitive to DOM state and occasionally produces a flaky
      #   "color-contrast" violation. Overriding to a solid-alpha version of
      #   the same OKLCH color gives axe a deterministic value to test against,
      #   without changing the production visual design.
      # Synchronous DOM mutation, no return value -> cdp_execute (raw statement).
      cdp_execute(<<~JS)
        document.querySelectorAll('[data-controller="toast-pill"], [data-controller="toast-card"]').forEach(el => {
          el.style.transition = 'none';
          el.style.opacity = '1';
          el.style.transform = 'none';

          // Replace the computed background with a solid (no-alpha) version.
          // getComputedStyle returns rgba(r, g, b, a) — drop the alpha to 1.
          const bg = getComputedStyle(el).backgroundColor;
          const match = bg.match(/rgba?\\(([^)]+)\\)/);
          if (match) {
            const parts = match[1].split(',').map(s => s.trim());
            el.style.backgroundColor = `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
          }
        });

        // Force a synchronous reflow so the style overrides are reflected
        // in computed styles before axe queries them.
        document.body.offsetHeight;
      JS

      # Audits at WCAG 2.2 Level AAA — the project's design target. The full
      # CUMULATIVE tag set (2.0+2.1+2.2 at A/AA/AAA): the previous
      # wcag2aaa-only filter ran just axe's 3 AAA-only rules and its comment
      # wrongly credited a "wcag22aaa" tag that was never passed (and which
      # covers no 44px rule anyway — the mc-* custom checks in run_axe_audit
      # handle 44px targets, focus indicators, and over-media transparency).
      # Fully qualified: this block's LEXICAL scope is outside the module, so
      # a bare constant NameErrors even though config.include provides the
      # METHODS.
      #
      # BOTH themes, each set EXPLICITLY. This hook used to audit whatever
      # theme the page happened to be in when the example ended, which made the
      # verdict a function of test choreography rather than of the UI: the same
      # command on the same code would catch a violation on one run and miss it
      # on the next (#541). It also meant a page's dark rendering was audited
      # only if some example happened to leave it dark.
      #
      # Auditing both is what closes the real gap. Dedicated `*_in_both_themes`
      # examples cover themes but only for the states THEY set up — the
      # deactivated-member badge fixed in #540 was never rendered by one, so a
      # dark-only contrast bug sat on main under a green CI.
      violations = %w[light dark].flat_map do |theme|
        set_theme(theme)
        results = run_axe_audit(AxeAccessibility::DEFAULT_AXE_OPTIONS.dup)
        (results["violations"] || []).map { |v| v.merge("themeContext" => theme) }
      end

      AxeAccessibility::TEARDOWN_LEDGER[example.id] = :audited

      formatted = violations.map { |v| "[#{v['themeContext'].upcase}] #{format_violation(v)}" }

      # rspec-rails' failure screenshot runs before config-level after hooks,
      # so a teardown-audit failure had no picture; take one here, named after
      # the example, into the directory CI already uploads.
      if violations.any?
        shot = Rails.root.join("tmp/capybara", "axe_teardown_#{example.full_description.parameterize.first(120)}.png")
        begin
          page.save_screenshot(shot)
          formatted << "[Screenshot Image]: #{shot}"
        rescue StandardError
          formatted << "[Screenshot unavailable]"
        end
      end

      expect(violations).to be_empty,
        "Accessibility violations found:#{formatted.join("\n")}"
    end

    config.prepend AxeAccessibility::VisitTracking, type: :system

    # The gate that keeps the hook above from going quiet again (#912): every
    # system example that navigated must have an :audited entry. Raising here
    # fails the run as a suite-level error; each parallel worker checks its
    # own examples.
    config.after(:suite) do
      ran = RSpec.world.all_examples.select do |ex|
        ex.metadata[:type] == :system && ex.execution_result.started_at &&
          ex.execution_result.status != :pending
      end
      missing = AxeAccessibility.unaudited(ran.map(&:id))
      next if missing.empty?

      raise "The AAA teardown audit did not run for #{missing.size} system " \
            "example(s) that navigated — the audit is not optional:\n  " \
            "#{missing.join("\n  ")}"
    end
  else
    config.before(:suite) do
      warn "\n*** SKIP_AXE=1: the WCAG 2.2 AAA teardown audit is OFF for this run. " \
           "A focused local loop only — never in CI or before a push. ***\n"
    end
  end
end
