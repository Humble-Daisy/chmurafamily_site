require "rails_helper"

# A fork rewrites its public pages, so a template spec that opens one breaks there.
RSpec.describe "Template specs and fork-owned pages" do
  let(:fork_page_visit) { /\b(?:visit|get)\b\(?\s*(?:root_path|root_url|page_path|page_url|["']\/(?:about|privacy|contact)?["'])/ }
  let(:fork_owned_specs) do
    File.readlines(Rails.root.join(".gitattributes"))
      .filter_map { |line| line[%r{\A(spec/\S+) merge=ours}, 1] }
  end

  def repo_path(file) = Pathname(file).relative_path_from(Rails.root).to_s

  it "recognizes each way a spec opens one" do
    [ "visit root_path", "visit(root_path)", 'visit "/"', "visit '/'", 'get "/"', "get root_url",
      "visit page_path(:about)", 'visit "/privacy"' ].each do |line|
      expect(line).to match(fork_page_visit)
    end
    [ "visit new_session_path", 'visit "/docs"', "get workspaces_path" ].each do |line|
      expect(line).not_to match(fork_page_visit)
    end
  end

  it "knows which specs a fork owns" do
    expect(fork_owned_specs).to include("spec/system/pages/**", "spec/requests/pages_spec.rb")
  end

  it "opens them only from fork-owned specs" do
    offenders = Dir[Rails.root.join("spec/**/*_spec.rb")].reject { |file|
      file == __FILE__ || fork_owned_specs.any? { |glob| File.fnmatch?(glob, repo_path(file), File::FNM_PATHNAME) }
    }.flat_map { |file|
      File.readlines(file).each_with_index.filter_map { |line, i| "#{repo_path(file)}:#{i + 1}" if line.match?(fork_page_visit) }
    }

    expect(offenders).to be_empty,
      "these specs open a page a fork rewrites. Visit new_session_path for app chrome, or move the test under spec/system/pages:\n#{offenders.join("\n")}"
  end
end
