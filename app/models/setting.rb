class Setting < ApplicationRecord
  has_secure_token :status_board_token, length: 32

  encrypts :ssh_private_key

  # Written to the storage volume so the README's one-liner can read it:
  #   docker compose exec -T kamal-ui cat storage/kamal-ui.pub >> ~/.ssh/authorized_keys
  PUBLIC_KEY_FILE = "kamal-ui.pub"
  AUTHORIZE_THIS_SERVER = "mkdir -p ~/.ssh && docker compose exec -T kamal-ui cat storage/#{PUBLIC_KEY_FILE} >> ~/.ssh/authorized_keys".freeze

  def self.instance
    first || create!
  end

  def regenerate_status_board_token!
    regenerate_status_board_token
  end

  # The key Kamal UI uses for servers when a project has none of its own,
  # generated on first use. Returns true when a new key was created.
  def ensure_ssh_key!
    if ssh_private_key.present?
      write_public_key_file
      return false
    end

    Dir.mktmpdir("kamal-ui-key") do |dir|
      path = File.join(dir, "id_ed25519")
      _, status = Open3.capture2e("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "kamal-ui", "-f", path)
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
    "mkdir -p ~/.ssh && echo '#{ssh_public_key}' >> ~/.ssh/authorized_keys" if ssh_public_key.present?
  end

  def ignore_service!(service)
    update!(ignored_services: ignored_services | [ service ])
  end
end
