require "open3"

# How Kamal Web trusts the servers it reaches over SSH: Kamal (net-ssh), the
# system ssh used for consoles and followed logs, git and monitoring all share
# one known_hosts file in the storage volume, so a key is remembered across
# deploys.
#
# By default a server's key is trusted the first time Kamal Web connects and
# refused if it changes later. With KAMAL_WEB_SSH_HOST_KEYS=strict, Kamal Web
# only connects to servers whose key was trusted beforehand on the server's
# page, after comparing its fingerprint with the one the server shows.
module SshHostKeys
  CONFIG_MARKER = "# Written by Kamal Web".freeze

  Key = Data.define(:type, :fingerprint, :line)

  module_function

  def strict?
    ENV["KAMAL_WEB_SSH_HOST_KEYS"] == "strict"
  end

  # The value of OpenSSH's StrictHostKeyChecking.
  def checking
    strict? ? "yes" : "accept-new"
  end

  def net_ssh_verify
    strict? ? :always : :accept_new
  end

  def known_hosts
    File.join(Dir.home, ".ssh", "known_hosts")
  end

  # Kamal starts net-ssh without host key options, so it reads them from
  # ~/.ssh/config. A config someone wrote by hand is left alone.
  def write_config!
    path = File.join(Dir.home, ".ssh", "config")
    return if File.exist?(path) && !File.read(path).start_with?(CONFIG_MARKER)

    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, <<~CONFIG)
      #{CONFIG_MARKER} on boot from KAMAL_WEB_SSH_HOST_KEYS. Changes are overwritten.
      Host *
        StrictHostKeyChecking #{checking}
        UserKnownHostsFile #{known_hosts}
    CONFIG
    File.chmod(0o600, path)
  rescue SystemCallError => error
    Rails.logger.warn "Could not write ~/.ssh/config: #{error.message}"
  end

  # known_hosts names servers on another port than 22 as [host]:port.
  def entry(host, port)
    port.to_i == 22 ? host : "[#{host}]:#{port}"
  end

  def trusted(host, port)
    return [] unless File.exist?(known_hosts)

    output, = Open3.capture2e("ssh-keygen", "-l", "-F", entry(host, port), "-f", known_hosts)
    parse(output)
  end

  # Asks the server for its keys, without trusting them.
  def scan(host, port)
    lines, status = Open3.capture2("ssh-keyscan", "-T", "5", "-p", port.to_s, host, err: File::NULL)
    return [] unless status.success?

    lines.lines.reject { |line| line.start_with?("#") || line.blank? }.filter_map do |line|
      output, = Open3.capture2("ssh-keygen", "-l", "-f", "-", stdin_data: line)
      parse(output).first&.with(line: line.strip)
    end
  end

  # Trusts the server's key with this fingerprint, if it still offers it.
  def trust!(host, port, fingerprint)
    key = scan(host, port).find { |candidate| candidate.fingerprint == fingerprint.to_s.strip }
    return false unless key

    FileUtils.mkdir_p(File.dirname(known_hosts), mode: 0o700)
    File.open(known_hosts, "a", 0o600) { |file| file.puts(key.line) }
    true
  end

  # For a server whose key changed on purpose, e.g. after a reinstall.
  def forget!(host, port)
    Open3.capture2e("ssh-keygen", "-R", entry(host, port), "-f", known_hosts) if File.exist?(known_hosts)
    FileUtils.rm_f("#{known_hosts}.old")
  end

  # ssh-keygen -l prints "256 SHA256:… host (ED25519)" for a key, and
  # "host ED25519 SHA256:…" for a known_hosts entry found with -F.
  def parse(output)
    output.lines.filter_map do |line|
      next if line.start_with?("#")

      if (match = line.match(/\A\d+\s+(SHA256:\S+)\s+.*\((\w+)\)\s*\z/))
        Key.new(type: match[2], fingerprint: match[1], line: nil)
      elsif (match = line.match(/\A\S+\s+(\S+)\s+(SHA256:\S+)\s*\z/))
        Key.new(type: match[1], fingerprint: match[2], line: nil)
      end
    end
  end
end
