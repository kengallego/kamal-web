class Setting < ApplicationRecord
  has_secure_token :status_board_token, length: 32

  encrypts :ssh_private_key

  # Written to the storage volume for bin/authorize-key, which the
  # `kamal authorize` alias in config/deploy.yml runs on the server.
  PUBLIC_KEY_FILE = "kamal-web.pub"
  AUTHORIZE_THIS_SERVER = "kamal authorize".freeze

  def self.instance
    first || create!
  end

  def update_available?
    latest_version.present? && Gem::Version.correct?(latest_version) && Gem::Version.new(latest_version) > Gem::Version.new(KamalWeb::VERSION)
  end

  def status_board_viewer?(token)
    status_board_enabled? && token.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(status_board_token.to_s, token)
  end

  def regenerate_status_board_token!
    regenerate_status_board_token
  end

  # The key Kamal Web uses for servers when a project has none of its own,
  # generated on first use. Returns true when a new key was created.
  def ensure_ssh_key!
    if ssh_private_key.present?
      write_public_key_file
      return false
    end

    Dir.mktmpdir("kamal-web-key") do |dir|
      path = File.join(dir, "id_ed25519")
      _, status = Open3.capture2e("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "kamal-web", "-f", path)
      raise "ssh-keygen failed" unless status.success?

      update!(ssh_private_key: File.read(path), ssh_public_key: File.read("#{path}.pub").strip)
    end
    write_public_key_file
    true
  end

  def write_public_key_file
    File.write(Rails.root.join("storage", PUBLIC_KEY_FILE), "#{ssh_public_key}\n")
  rescue SystemCallError
    # Only a convenience for the README command; Settings shows the key too.
  end

  def authorize_command
    if ssh_public_key.present?
      "mkdir -p -m 700 ~/.ssh && touch ~/.ssh/authorized_keys && (grep -qxF '#{ssh_public_key}' ~/.ssh/authorized_keys || echo '#{ssh_public_key}' >> ~/.ssh/authorized_keys)"
    end
  end

  def ignore_service!(service)
    update!(ignored_services: ignored_services | [ service ])
  end
end
