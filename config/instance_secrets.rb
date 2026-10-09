require "securerandom"
require "fileutils"
require "active_support/key_generator"

# Self-hosted instances must work without RAILS_MASTER_KEY or credentials, so the
# secret_key_base is taken from SECRET_KEY_BASE or generated once and persisted
# next to the databases. Losing it makes encrypted columns unreadable.
module InstanceSecrets
  ROOT = File.expand_path("..", __dir__)

  module_function

  def secret_key_base
    @secret_key_base ||= ENV["SECRET_KEY_BASE"].presence || (ENV["SECRET_KEY_BASE_DUMMY"] ? "dummy" : read_or_create(secret_path))
  end

  def encryption_key(purpose)
    ENV["ACTIVE_RECORD_ENCRYPTION_#{purpose.upcase}"].presence ||
      ActiveSupport::KeyGenerator.new(secret_key_base, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
        .generate_key("active_record_encryption/#{purpose}", 32).unpack1("H*")
  end

  def secret_path
    if ENV.fetch("RAILS_ENV", "development") == "production"
      File.join(ROOT, "storage", "secret_key_base")
    else
      File.join(ROOT, "tmp", "local_secret.txt")
    end
  end

  def read_or_create(path)
    return File.read(path).strip if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    SecureRandom.hex(64).tap do |secret|
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(secret) }
    end
  rescue Errno::EEXIST
    File.read(path).strip
  end
end
