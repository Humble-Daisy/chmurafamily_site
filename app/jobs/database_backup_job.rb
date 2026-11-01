# frozen_string_literal: true

class DatabaseBackupJob < ApplicationJob
  queue_as :default

  def perform
    DatabaseBackup.new.take!
  end
end
