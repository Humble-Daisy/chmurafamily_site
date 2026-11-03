require "rails_helper"

RSpec.describe "bin/setup" do
  let(:script) { Rails.root.join("bin/setup").read }

  it "installs the Lefthook git hooks, so a fresh clone checks its commits and pushes" do
    expect(script).to include('system! "bundle exec lefthook install"')
  end
end
