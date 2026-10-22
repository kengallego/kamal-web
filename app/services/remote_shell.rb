require "net/ssh"

# Short read-only SSH commands used for monitoring and proxy inspection. Uses
# the SSH user and port from the project's Kamal config, or a server's own.
class RemoteShell
  class Error < StandardError; end

  TIMEOUT = 10

  def self.for_server(server)
    allocate.tap { |shell| shell.send(:connect_as, server.host, user: server.effective_ssh_user, port: server.effective_ssh_port, keys: server.ssh_keys) }
  end

  def initialize(project, host, destination: nil)
    config = project.config_for(destination.to_s).presence || project.config_for(project.destinations.first)
    connect_as(host, user: config.ssh_user, port: config.ssh_port, keys: project.ssh_keys)
  end

  # input is sent on stdin, which keeps passwords out of the server's
  # process list. With check, a non-zero exit status raises Error.
  def run(command, input: nil, check: false)
    Net::SSH.start(@host, @user, **options) do |ssh|
      output = +""
      status = nil
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
          raise Error, "Could not run command on #{@host}" unless success
          ch.on_data { |_, data| output << data }
          ch.on_extended_data { |_, _, data| output << data }
          ch.on_request("exit-status") { |_, data| status = data.read_long }
          if input
            ch.send_data(input)
            ch.eof!
          end
        end
      end
      channel.wait
      raise Error, "#{@host}: #{output.strip.presence || "exit status #{status}"}" if check && status != 0
      output
    end
  rescue Net::SSH::Exception, SystemCallError, SocketError, Timeout::Error, OpenSSL::PKey::PKeyError, ArgumentError => error
    # Some Net::SSH errors carry only their class name, e.g. ConnectionTimeout.
    message = error.message == error.class.name ? "#{error.class.name.demodulize.underscore.humanize.downcase} (SSH port #{@port})" : error.message
    raise Error, "#{@host}: #{message}"
  end

  private
    def connect_as(host, user:, port:, keys:)
      @host, @user, @port, @keys = host, user, port, keys
    end

    def options
      {
        port: @port,
        key_data: @keys,
        keys: [],
        keys_only: @keys.any?,
        non_interactive: true,
        timeout: TIMEOUT,
        verify_host_key: SshHostKeys.net_ssh_verify,
        user_known_hosts_file: SshHostKeys.known_hosts,
        logger: Logger.new(File::NULL)
      }
    end
end
