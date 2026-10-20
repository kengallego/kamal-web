# Kamal shells out to the system ssh for interactive commands and followed
# logs. Nobody can answer its host key prompt from the UI, so child processes
# get an ssh first in PATH that never asks: it trusts new hosts on first use or
# only pre-trusted ones, as SshHostKeys says, and always refuses changed keys.
module SshWrapper
  module_function

  def directory
    @directory ||= begin
      dir = Rails.root.join("tmp/kamal_web_bin")
      dir.mkpath
      SshHostKeys.write_config!
      script = dir.join("ssh")
      script.write(<<~SH)
        #!/bin/sh
        exec #{Shellwords.escape(real_ssh)} -o StrictHostKeyChecking=#{SshHostKeys.checking} -o UserKnownHostsFile=#{Shellwords.escape(SshHostKeys.known_hosts)} -o ServerAliveInterval=30 "$@"
      SH
      script.chmod(0o755)
      dir.to_s
    end
  end

  def real_ssh
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |path| File.join(path, "ssh") }
      .find { |path| File.executable?(path) && !path.start_with?(Rails.root.join("tmp").to_s) } || "/usr/bin/ssh"
  end
end
