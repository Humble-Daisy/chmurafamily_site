# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Theme preference", type: :system do
  def emulate_os_scheme(scheme)
    cdp_command("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: scheme } ])
  end

  def theme_value = page.evaluate_script("document.documentElement.dataset.themeThemeValue")

  after { cdp_command("Emulation.setEmulatedMedia", features: []) }

  it "follows the OS with no saved preference, including a change while the page is open" do
    emulate_os_scheme("dark")
    visit root_path
    expect(page).to have_css("html.dark")

    emulate_os_scheme("light")
    expect(page).to have_no_css("html.dark")
  end

  it "cycles light, dark, then back to following the OS" do
    visit root_path
    toggle = find("[data-controller='theme-toggle']")

    stops = 3.times.map do
      toggle.click
      theme_value
    end

    expect(stops).to eq(%w[light dark system])
  end
end
