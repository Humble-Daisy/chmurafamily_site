# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseBackup do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:service) { DatabaseBackup::Bucket.new(ActiveStorage::Service::DiskService.new(root: dir.join("bucket").to_s)) }
  let(:database) { dir.join("production.sqlite3") }
  let(:backup) { described_class.new(database: database, destination: service, deployment: "production") }

  def write_rows(path, *names)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("PRAGMA journal_mode = WAL")
      db.execute("CREATE TABLE IF NOT EXISTS people (name TEXT)")
      names.each { |name| db.execute("INSERT INTO people (name) VALUES (?)", [ name ]) }
    end
  end

  def names_in(path)
    db = SQLite3::Database.new(path.to_s)
    db.execute("SELECT name FROM people ORDER BY name").flatten.tap { db.close }
  end

  after { FileUtils.rm_rf(dir) }

  describe "#take!" do
    it "uploads a compressed copy of the database that opens with its rows" do
      write_rows(database, "ada", "grace")

      key = backup.take!

      copy = dir.join("copy.sqlite3")
      File.binwrite(copy, Zlib.gunzip(service.download(key)))
      expect(names_in(copy)).to eq(%w[ada grace])
    end

    it "files each backup under its deployment, by time, and points latest at it" do
      write_rows(database, "ada")

      travel_to Time.utc(2026, 11, 1, 14, 0, 5) do
        expect(backup.take!).to eq("backups/production/2026-11-01T140005Z.sqlite3.gz")
      end
      expect(backup.latest).to eq("backups/production/2026-11-01T140005Z.sqlite3.gz")
    end

    it "keeps one deployment's latest apart from another's" do
      write_rows(database, "ada")
      staging = described_class.new(database: database, destination: service, deployment: "staging")

      production_key = backup.take!
      staging.take!

      expect(backup.latest).to eq(production_key)
    end
  end

  describe ".destination" do
    it "is the object_storage bucket by default" do
      expect(described_class.destination({})).to be_a(DatabaseBackup::Bucket)
    end

    it "is a folder when BACKUP_PATH names one, kept for BACKUP_RETENTION_DAYS" do
      destination = described_class.destination({ "BACKUP_PATH" => dir.to_s, "BACKUP_RETENTION_DAYS" => "7" })

      expect(destination).to be_a(DatabaseBackup::Folder)
      expect(destination.retention).to eq(7.days)
    end
  end

  describe "pruning" do
    it "asks the destination to prune after each backup, keeping the new one" do
      write_rows(database, "ada")
      allow(service).to receive(:prune)

      key = backup.take!

      expect(service).to have_received(:prune).with("backups/production", keep: key)
    end
  end

  describe "#latest" do
    it "is nil before the first backup" do
      expect(backup.latest).to be_nil
    end
  end

  describe "#restore!" do
    it "puts the latest backup in place of the database and keeps the old file beside it" do
      write_rows(database, "ada")
      backup.take!
      write_rows(database, "mallory")

      set_aside = backup.restore!

      expect(names_in(database)).to eq(%w[ada])
      expect(names_in(set_aside)).to eq(%w[ada mallory])
    end

    it "removes the old database's WAL files, which belong to the file set aside" do
      write_rows(database, "ada")
      backup.take!
      FileUtils.touch([ "#{database}-wal", "#{database}-shm" ])

      backup.restore!

      expect(File.exist?("#{database}-wal")).to be(false)
      expect(File.exist?("#{database}-shm")).to be(false)
    end

    it "restores a named backup instead of the latest" do
      write_rows(database, "ada")
      first = backup.take!
      write_rows(database, "grace")
      travel 1.hour do
        backup.take!
      end

      backup.restore!(first)

      expect(names_in(database)).to eq(%w[ada])
    end

    it "refuses a backup that isn't a sound database, and leaves the current one in place" do
      write_rows(database, "ada")
      service.upload("backups/production/broken.sqlite3.gz", StringIO.new(Zlib.gzip("not a database")))

      expect { backup.restore!("backups/production/broken.sqlite3.gz") }.to raise_error(DatabaseBackup::Corrupt)
      expect(names_in(database)).to eq(%w[ada])
    end

    it "refuses when there is no backup to restore" do
      write_rows(database, "ada")

      expect { backup.restore! }.to raise_error(DatabaseBackup::Missing, /no backup/i)
      expect(names_in(database)).to eq(%w[ada])
    end
  end
end
