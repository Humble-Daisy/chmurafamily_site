require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/branch-changes" do
  let(:repo) { Pathname.new(Dir.mktmpdir) }
  let(:script) { Rails.root.join("bin/branch-changes").to_s }

  after { FileUtils.rm_rf(repo) }

  def git(*args)
    system(CleanGitEnv::HASH, "git", "-C", repo.to_s, "-c", "user.email=t@example.com", "-c", "user.name=T", *args,
           out: File::NULL, err: File::NULL, exception: true)
  end

  def commit_file(name)
    repo.join(name).write("x\n")
    git("add", name)
    git("commit", "-qm", name)
  end

  def changes
    out, status = Open3.capture2(CleanGitEnv::HASH, script, chdir: repo.to_s)
    raise "exit #{status.exitstatus}" unless status.success?

    out.lines(chomp: true)
  end

  before do
    git("init", "-q", "-b", "work")
    commit_file("old.txt")
  end

  it "compares with origin/main when it exists, as on a fork with both branches" do
    git("update-ref", "refs/remotes/origin/main", "HEAD")
    git("update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("on_next.txt")
    git("update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("new.txt")

    expect(changes).to contain_exactly("on_next.txt", "new.txt")
  end

  it "compares with origin/next on a Fork-button fork, which has no main yet" do
    git("update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("new.txt")

    expect(changes).to eq([ "new.txt" ])
  end

  it "lists every tracked file on a first push to an empty repository" do
    commit_file("new.txt")

    expect(changes).to contain_exactly("old.txt", "new.txt")
  end
end
