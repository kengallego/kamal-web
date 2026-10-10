# Applies a backup staged by Settings → Restore, before the app opens the
# database. Runs from bin/docker-entrypoint. The replaced files are kept in
# storage/before-restore-<time>/.
require "fileutils"
require "rubygems/package"
require "zlib"

storage = ENV.fetch("KAMAL_WEB_STORAGE_PATH", File.expand_path("../storage", __dir__))
staged = File.join(storage, "restore.tar.gz")
exit unless File.exist?(staged)

entries = {}
Zlib::GzipReader.open(staged) do |gzip|
  Gem::Package::TarReader.new(gzip).each do |entry|
    entries[entry.full_name] = entry.read if entry.file? && %w[ database.sqlite3 secret_key_base ].include?(entry.full_name)
  end
end

if entries.size == 2
  previous = File.join(storage, "before-restore-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}")
  FileUtils.mkdir_p(previous)
  Dir[File.join(storage, "{production.sqlite3,production.sqlite3-*,secret_key_base}")].each { |file| FileUtils.mv(file, previous) }

  File.binwrite(File.join(storage, "production.sqlite3"), entries["database.sqlite3"])
  File.write(File.join(storage, "secret_key_base"), entries["secret_key_base"].strip)
  File.chmod(0o600, File.join(storage, "secret_key_base"))
  puts "Restored the backup. The previous database and key are in #{previous}."
else
  puts "Ignored #{staged}: it doesn't contain a database and a secret key."
end

FileUtils.mv(staged, File.join(storage, "restore-applied-#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}.tar.gz"))
