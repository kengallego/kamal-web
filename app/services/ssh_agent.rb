require "open3"

# Runs a throwaway ssh-agent holding the project's keys, so keys are never
# written to disk and both git and Kamal (net-ssh) can use them.
class SshAgent
  class Error < StandardError; end

  def self.with_keys(keys, &block)
    new(keys).run(&block)
  end

  def initialize(keys)
    @keys = Array(keys).compact_blank
  end

  def run
    return yield({}) if @keys.empty?

    Dir.mktmpdir("kamal-ui-agent") do |dir|
      socket = File.join(dir, "agent.sock")
      pid = Process.spawn("ssh-agent", "-D", "-a", socket, out: File::NULL, err: File::NULL)

      begin
        wait_for(socket)
        @keys.each { |key| add(socket, key) }
        yield({ "SSH_AUTH_SOCK" => socket })
      ensure
        Process.kill("TERM", pid) rescue Errno::ESRCH
        Process.wait(pid) rescue Errno::ECHILD
      end
    end
  end

  private
    def wait_for(socket)
      50.times do
        return if File.socket?(socket)
        sleep 0.1
      end
      raise Error, "ssh-agent did not start"
    end

    def add(socket, key)
      output, status = Open3.capture2e({ "SSH_AUTH_SOCK" => socket }, "ssh-add", "-", stdin_data: "#{key.strip.gsub("\r\n", "\n")}\n")
      raise Error, "Could not load SSH key (keys with a passphrase are not supported): #{output.strip}" unless status.success?
    end
end
