require "rails_helper"

# Holds ui-patterns.md's recipes to the views they name (developer/ui-patterns.md §Recipes).
RSpec.describe "UI recipes" do
  let(:page) { Rails.root.join("app/docs/developer/ui-patterns.md").read.split(/^---\s*$/, 3) }
  let(:text) { page[2] }
  let(:recipes) { YAML.safe_load(page[1]).fetch("code", {}) }

  def shared_partial?(path) = path.start_with?("app/views/shared/")

  def reference_view?(path) = path.start_with?("app/views/") && !path.start_with?("app/views/shared/", "app/views/layouts/")

  def render_name(partial) = partial.delete_prefix("app/views/").sub("/_", "/").delete_suffix(".html.erb")

  it "indexes the recipes it was written against (floor)" do
    expect(recipes.size).to be >= 6
  end

  it "names every indexed path in its text" do
    unnamed = recipes.values.flatten.uniq.reject { |path| text.include?("`#{path}`") }

    expect(unnamed).to be_empty, "indexed in the front matter, never named in the page: #{unnamed.join(', ')}"
  end

  it "gives every recipe a shared partial and a view to copy from" do
    bare = recipes.reject { |_, paths| paths.any? { |p| shared_partial?(p) } && paths.any? { |p| reference_view?(p) } }

    expect(bare.keys).to be_empty, "recipes naming no shared partial, or no reference view: #{bare.keys.join(', ')}"
  end

  it "names only partials that something else in the recipe renders" do
    # A recipe that copies from a fork-owned page is checked beside that page, in spec/requests/pages_spec.rb.
    template_recipes = recipes.reject { |_, paths| paths.any? { |path| path.start_with?("app/views/pages/") } }
    unrendered = template_recipes.flat_map do |recipe, paths|
      views = paths.select { |p| p.start_with?("app/views/") && p.end_with?(".erb") }
      paths.select { |p| shared_partial?(p) }
        .reject { |partial| (views - [ partial ]).any? { |view| Rails.root.join(view).read.include?(render_name(partial)) } }
        .map { |partial| "#{recipe}: nothing it names renders #{render_name(partial)}" }
    end

    expect(unrendered).to be_empty, unrendered.join("\n")
  end
end
