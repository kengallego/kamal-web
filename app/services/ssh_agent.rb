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
    yield start
  ensure
    stop
  end

  # Starts the agent and returns the environment pointing at it. Call #stop
  # when done; long-lived callers (the web console) can't use a block.
  def start
    return {} if @keys.empty?

    @dir = Dir.mktmpdir("kamal-ui-agent")
    socket = File.join(@dir, "agent.sock")
    @pid = Process.spawn("ssh-agent", "-D", "-a", socket, out: File::NULL, err: File::NULL)
    wait_for(socket)
    @keys.each { |key| add(socket, key) }
    { "SSH_AUTH_SOCK" => socket }
  end

  def stop
    if @pid
      Process.kill("TERM", @pid) rescue Errno::ESRCH
      Process.wait(@pid) rescue Errno::ECHILD
      @pid = nil
    end
    FileUtils.rm_rf(@dir) if @dir
    @dir = nil
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
