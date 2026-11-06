# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Skip-to-content link", type: :system do
  def focused_box
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.activeElement
        const box = el.getBoundingClientRect()
        return { href: el.getAttribute("href"), width: box.width, height: box.height }
      })()
    JS
  end

  it "is the first thing Tab reaches, and shows itself when focused" do
    visit "/docs"
    cdp_press("Tab")

    box = focused_box
    expect(box["href"]).to eq("#main-content")
    expect(box["width"]).to be > 1
    expect(box["height"]).to be > 1
  end
end
