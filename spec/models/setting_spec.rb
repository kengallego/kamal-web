require "rails_helper"

RSpec.describe Setting do
  it "generates its SSH key once and publishes the public half for kamal authorize" do
    setting = Setting.instance
    path = Rails.root.join("storage", Setting::PUBLIC_KEY_FILE)
    File.delete(path) if path.exist?

    expect(setting.ensure_ssh_key!).to be(true)
    expect(setting.ssh_private_key).to include("PRIVATE KEY")
    expect(path.read).to eq("#{setting.ssh_public_key}\n")
    expect(setting.ssh_public_key).to start_with("ssh-ed25519 ")

    File.delete(path)
    expect(setting.ensure_ssh_key!).to be(false)
    expect(path.read).to eq("#{setting.ssh_public_key}\n")
  ensure
    File.delete(path) if path&.exist?
  end

  it "authorizes the key once, however often the command runs" do
    setting = Setting.instance
    setting.ensure_ssh_key!

    Dir.mktmpdir do |home|
      [ setting.authorize_command, `#{Rails.root.join("bin/authorize-key")}` ].each do |command|
        2.times { system({ "HOME" => home }, "sh", "-c", command, out: File::NULL, exception: true) }
      end
      expect(File.read(File.join(home, ".ssh/authorized_keys"))).to eq("#{setting.ssh_public_key}\n")
    end
  ensure
    File.delete(Rails.root.join("storage", Setting::PUBLIC_KEY_FILE)) if Rails.root.join("storage", Setting::PUBLIC_KEY_FILE).exist?
  end
end
