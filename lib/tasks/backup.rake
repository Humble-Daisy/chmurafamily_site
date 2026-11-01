namespace :backup do
  desc "Back up the database to the object_storage bucket now"
  task now: :environment do
    puts "Backed up to #{DatabaseBackup.new.take!}"
  end

  desc "Name the latest backup of the database"
  task status: :environment do
    latest = DatabaseBackup.new.latest
    puts latest ? "Latest: #{latest}" : "No backup yet."
  end

  desc "Replace the database with the latest backup, or backup:restore[KEY]; stop the app first"
  task :restore, [ :key ] => :environment do |_task, args|
    set_aside = DatabaseBackup.new.restore!(args[:key])
    puts "Restored. The database it replaced is at #{set_aside}."
  end
end
