require "rubygems/package"
require "zlib"

# A backup of everything that can't be recreated: the main database (projects,
# encrypted secrets, history) and the secret_key_base that decrypts it. Clones,
# caches and queues are left out.
#
# Restoring stages the archive as storage/restore.tar.gz; script/apply_restore.rb
# swaps the files in when the container next boots, before the database opens.
module InstanceBackup
  # The message is a key under flash.backups.invalid.
  class Invalid < StandardError; end

  APP = "kamal-web".freeze
  ENTRIES = %w[ manifest.json database.sqlite3 secret_key_base ].freeze
  MAX_SIZE = 500.megabytes
  STAGED_PATH = Rails.root.join("storage", "restore.tar.gz")
  # Scheduled backups, when turned on in Settings.
  DIRECTORY = Rails.root.join("storage", "backups")
  STORED_NAME = /\Akamal-web-backup-\d{8}-\d{6}\.tar\.gz\z/

  module_function

  def filename
    "kamal-web-backup-#{Time.current.strftime("%Y%m%d-%H%M%S")}.tar.gz"
  end

  def write(io)
    Dir.mktmpdir("kamal-web-backup") do |dir|
      database = File.join(dir, "database.sqlite3")
      # VACUUM INTO writes a consistent copy while the app keeps running.
      ActiveRecord::Base.connection.execute("VACUUM INTO #{ActiveRecord::Base.connection.quote(database)}")
      manifest = { app: APP, version: KamalWeb::VERSION, created_at: Time.current.iso8601 }.to_json

      gzip = Zlib::GzipWriter.new(io)
      Gem::Package::TarWriter.new(gzip) do |tar|
        add(tar, "manifest.json", manifest)
        add(tar, "database.sqlite3", File.binread(database))
        add(tar, "secret_key_base", Rails.application.secret_key_base)
      end
      gzip.finish
    end
    io
  end

  # Writes a backup into the volume and deletes the oldest beyond keep.
  def store!(keep:)
    FileUtils.mkdir_p(DIRECTORY, mode: 0o700)
    path = DIRECTORY.join(filename)
    partial = DIRECTORY.join(".#{path.basename}.partial")
    File.open(partial, "wb", 0o600) { |file| write(file) }
    File.rename(partial, path)
    stored.drop(keep).each(&:delete)
    path
  end

  # Newest first.
  def stored
    return [] unless DIRECTORY.directory?

    DIRECTORY.children.select { |path| path.file? && path.basename.to_s.match?(STORED_NAME) }.sort.reverse
  end

  def find_stored(name)
    stored.find { |path| path.basename.to_s == name.to_s }
  end

  # Checks an uploaded archive and keeps it for the next boot.
  def stage!(path)
    raise Invalid, "too_large" if File.size(path) > MAX_SIZE

    entries = read(path)
    manifest = JSON.parse(entries.fetch("manifest.json")) rescue nil
    raise Invalid, "not_backup" unless manifest.is_a?(Hash) && manifest["app"] == APP
    raise Invalid, "no_database" unless entries["database.sqlite3"].to_s.start_with?("SQLite format 3\0")
    raise Invalid, "no_key" if entries["secret_key_base"].to_s.strip.length < 32

    FileUtils.cp(path, STAGED_PATH)
    manifest
  end

  def read(path)
    entries = {}
    Zlib::GzipReader.open(path) do |gzip|
      Gem::Package::TarReader.new(gzip).each do |entry|
        entries[entry.full_name] = entry.read if entry.file? && ENTRIES.include?(entry.full_name)
      end
    end
    entries
  rescue Zlib::Error, Gem::Package::TarInvalidError, Gem::Package::FormatError
    raise Invalid, "not_archive"
  end

  def add(tar, name, content)
    tar.add_file_simple(name, 0o600, content.bytesize) { |file| file.write(content) }
  end
end
