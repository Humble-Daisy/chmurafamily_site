require "rails_helper"
require "rake"

RSpec.describe "backup rake tasks" do
  before(:all) { RakeTasks.load_once }

  let(:backup) { instance_double(DatabaseBackup) }

  before { allow(DatabaseBackup).to receive(:new).and_return(backup) }

  def run_task(name, *args)
    Rake::Task[name].reenable
    Rake::Task[name].invoke(*args)
  end

  it "backup:now takes a backup and names it" do
    allow(backup).to receive(:take!).and_return("backups/production/2026-11-01T140005Z.sqlite3.gz")

    expect { run_task("backup:now") }.to output(/backups\/production\/2026-11-01T140005Z\.sqlite3\.gz/).to_stdout
  end

  it "backup:status names the latest backup" do
    allow(backup).to receive(:latest).and_return("backups/production/2026-11-01T140005Z.sqlite3.gz")

    expect { run_task("backup:status") }.to output(/Latest: backups\/production\/2026-11-01T140005Z/).to_stdout
  end

  it "backup:status says so when there is none yet" do
    allow(backup).to receive(:latest).and_return(nil)

    expect { run_task("backup:status") }.to output(/No backup yet/).to_stdout
  end

  it "backup:restore restores the latest, or the backup it is given, and says where the old file went" do
    allow(backup).to receive(:restore!).and_return(Pathname("storage/production.sqlite3.before-restore"))

    expect { run_task("backup:restore") }.to output(/before-restore/).to_stdout
    expect(backup).to have_received(:restore!).with(nil)

    run_task("backup:restore", "backups/production/old.sqlite3.gz")
    expect(backup).to have_received(:restore!).with("backups/production/old.sqlite3.gz")
  end
end
