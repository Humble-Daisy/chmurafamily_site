# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "config/recurring.yml", type: :config do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }
  let(:production) { config.fetch("production") }

  it "schedules WorkspaceInvitationExpiringSweepJob every 6 hours" do
    entry = production.fetch("workspace_invitation_expiring_sweep")
    expect(entry["class"]).to eq("WorkspaceInvitationExpiringSweepJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to match(/every 6 hours/i)
  end

  it "schedules WorkspaceCapacitySweepJob every 12 hours" do
    entry = production.fetch("workspace_capacity_sweep")
    expect(entry["class"]).to eq("WorkspaceCapacitySweepJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to match(/every 12 hours/i)
  end

  it "backs up the database every hour" do
    entry = production.fetch("database_backup")
    expect(entry["class"]).to eq("DatabaseBackupJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to eq("every hour")
  end

  it "preserves the existing solid-queue clear-finished-jobs schedule" do
    entry = production.fetch("clear_solid_queue_finished_jobs")
    expect(entry["command"]).to include("SolidQueue::Job.clear_finished_in_batches")
  end
end
