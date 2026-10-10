require "net/ssh"

# Short read-only SSH commands used for monitoring and proxy inspection. Uses
# the SSH user and port from the project's Kamal config.
class RemoteShell
  class Error < StandardError; end

  TIMEOUT = 10

  def initialize(project, host, destination: nil)
    @project = project
    @host = host
    @config = project.config_for(destination.to_s).presence || project.config_for(project.destinations.first)
  end

  def run(command)
    Net::SSH.start(@host, @config.ssh_user, **options) do |ssh|
      output = +""
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
          raise Error, "Could not run command on #{@host}" unless success
          ch.on_data { |_, data| output << data }
          ch.on_extended_data { |_, _, data| output << data }
        end
      end
      channel.wait
      output
    end
  rescue Net::SSH::Exception, SystemCallError, SocketError, Timeout::Error, OpenSSL::PKey::PKeyError, ArgumentError => error
    # Some Net::SSH errors carry only their class name, e.g. ConnectionTimeout.
    message = error.message == error.class.name ? "#{error.class.name.demodulize.underscore.humanize.downcase} (SSH port #{@config.ssh_port})" : error.message
    raise Error, "#{@host}: #{message}"
  end

  private
    def options
      {
        port: @config.ssh_port,
        key_data: @project.ssh_keys,
        keys: [],
        keys_only: @project.ssh_keys.any?,
        non_interactive: true,
        timeout: TIMEOUT,
        verify_host_key: :accept_new,
        user_known_hosts_file: File.join(Dir.home, ".ssh", "known_hosts"),
        logger: Logger.new(File::NULL)
      }
    end
end
