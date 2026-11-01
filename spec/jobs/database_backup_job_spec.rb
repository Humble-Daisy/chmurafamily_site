require "rails_helper"

RSpec.describe DatabaseBackupJob, type: :job do
  it "takes a backup of the primary database" do
    backup = instance_double(DatabaseBackup, take!: "backups/production/key.sqlite3.gz")
    allow(DatabaseBackup).to receive(:new).and_return(backup)

    described_class.perform_now

    expect(backup).to have_received(:take!)
  end

  it "runs on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end
end
