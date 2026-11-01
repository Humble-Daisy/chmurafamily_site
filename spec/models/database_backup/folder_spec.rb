# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseBackup::Folder do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:folder) { described_class.new(root) }

  after { FileUtils.rm_rf(root) }

  it "stores each key at that path under the folder, so the backups can be browsed and copied by hand" do
    folder.upload("backups/production/2026-11-01T140005Z.sqlite3.gz", StringIO.new("snapshot"))

    expect(root.join("backups/production/2026-11-01T140005Z.sqlite3.gz").read).to eq("snapshot")
  end

  it "downloads what it stored, whole or in chunks" do
    folder.upload("backups/production/latest", StringIO.new("pointer"))

    expect(folder.download("backups/production/latest")).to eq("pointer")
    chunks = []
    folder.download("backups/production/latest") { |chunk| chunks << chunk }
    expect(chunks.join).to eq("pointer")
  end

  it "raises the same not-found error a bucket does" do
    expect { folder.download("backups/production/latest") }.to raise_error(ActiveStorage::FileNotFoundError)
  end

  it "prunes backups older than its retention, keeping the one just taken" do
    folder = described_class.new(root, retention: 30.days)
    names = %w[2026-09-01T000000Z 2026-10-15T000000Z 2026-11-01T140005Z].map { |time| "backups/production/#{time}.sqlite3.gz" }
    names.each { |key| folder.upload(key, StringIO.new("x")) }

    travel_to Time.utc(2026, 11, 1, 15) do
      folder.prune("backups/production", keep: names.last)
    end

    expect(names.map { |key| root.join(key).exist? }).to eq([ false, true, true ])
  end

  it "never prunes another deployment's backups" do
    folder.upload("backups/staging/2026-01-01T000000Z.sqlite3.gz", StringIO.new("x"))

    folder.prune("backups/production", keep: "backups/production/latest")

    expect(root.join("backups/staging/2026-01-01T000000Z.sqlite3.gz")).to exist
  end

  it "refuses to write onto the database's own filesystem, where a lost disk takes the backups too" do
    folder = described_class.new(root, apart_from: root)

    expect { folder.upload("backups/production/latest", StringIO.new("x")) }
      .to raise_error(DatabaseBackup::Folder::SameDisk, /same filesystem/)
  end
end
