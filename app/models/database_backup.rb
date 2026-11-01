# frozen_string_literal: true

class DatabaseBackup
  class Missing < StandardError; end
  class Corrupt < StandardError; end

  def initialize(database: Rails.root.join(ActiveRecord::Base.connection_db_config.database),
                 service: ActiveStorage::Blob.services.fetch(:object_storage),
                 deployment: DeployCredentials.deployment)
    @database = Pathname(database)
    @service = service
    @prefix = "backups/#{deployment}"
  end

  def take!
    key = "#{@prefix}/#{timestamp}.sqlite3.gz"

    Dir.mktmpdir do |dir|
      copy = File.join(dir, "copy.sqlite3")
      SQLite3::Database.new(@database.to_s) { |db| db.execute("VACUUM INTO ?", [ copy ]) }
      check_integrity!(copy)
      Zlib::GzipWriter.open("#{copy}.gz") { |gzip| File.open(copy, "rb") { |file| IO.copy_stream(file, gzip) } }
      File.open("#{copy}.gz", "rb") { |file| @service.upload(key, file) }
    end

    @service.upload(latest_pointer, StringIO.new(key))
    key
  end

  def latest
    @service.download(latest_pointer)
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  def restore!(key = nil)
    key ||= latest or raise Missing, "There is no backup to restore under #{@prefix}."

    Dir.mktmpdir(nil, @database.dirname) do |dir|
      restored = File.join(dir, "restored.sqlite3")
      File.open("#{restored}.gz", "wb") { |file| @service.download(key) { |chunk| file.write(chunk) } }
      Zlib::GzipReader.open("#{restored}.gz") { |gzip| File.open(restored, "wb") { |file| IO.copy_stream(gzip, file) } }
      check_integrity!(restored)

      set_aside_current.tap { File.rename(restored, @database) }
    end
  end

  private
    def latest_pointer = "#{@prefix}/latest"

    def timestamp = Time.current.utc.strftime("%Y-%m-%dT%H%M%SZ")

    def check_integrity!(path)
      db = SQLite3::Database.new(path, readonly: true)
      result = db.get_first_value("PRAGMA integrity_check")
      raise Corrupt, "#{path} failed SQLite's integrity check: #{result}" unless result == "ok"
    rescue SQLite3::Exception => error
      raise Corrupt, "#{path} isn't a sound SQLite database: #{error.message}"
    ensure
      db&.close
    end

    def set_aside_current
      Pathname("#{@database}.before-restore-#{timestamp}").tap do |set_aside|
        [ "", "-wal", "-shm" ].each do |suffix|
          File.rename("#{@database}#{suffix}", "#{set_aside}#{suffix}") if File.exist?("#{@database}#{suffix}")
        end
      end
    end
end
