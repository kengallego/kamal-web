require "pty"

# Runs a ConsoleSession's `kamal app exec --interactive` in a PTY and pipes it
# to the browser. Lives in the web process for as long as the WebSocket does.
class ConsoleProcess
  IDLE_TIMEOUT = 30.minutes
  READ_TIMEOUT = 1

  def initialize(session, on_output:, on_exit:, command: nil)
    @session = session
    @project = session.project
    @on_output = on_output
    @on_exit = on_exit
    @command = command
    @size = [ 24, 80 ]
    @last_activity = monotonic
  end

  def start
    @thread = Thread.new { Rails.application.executor.wrap { run } }
  end

  def write(data)
    @last_activity = monotonic
    @writer&.write(data)
  rescue IOError, Errno::EIO
    # The process is gone; the reader loop reports the exit.
  end

  def resize(rows, cols)
    return unless rows.between?(2, 500) && cols.between?(2, 1000)

    @size = [ rows, cols ]
    @reader&.winsize = @size
  rescue IOError, Errno::EIO
  end

  def stop
    @stopping = true
    signal("TERM")
    signal("KILL") unless @thread&.join(3)
    @thread&.join(1)
  end

  def running?
    @thread&.alive?
  end

  private
    def run
      agent = SshAgent.new(@project.ssh_keys)
      env = ProcessEnvironment.build(@project.environment_for(@session.destination).merge(agent.start))
        .merge("TERM" => "xterm-256color").except("NO_COLOR")

      workspace = ProjectWorkspace.new(@project, logger: ->(line) { output "\e[2m#{line}\e[0m\r\n" })
      workspace.prepare!(env, sync: @project.active_operation.nil?)
      return finish(nil) if @stopping

      @on_exit.call(spawn(env, workspace.path))
    rescue ProjectWorkspace::Error, SshAgent::Error => error
      output "\r\n\e[31m#{error.message}\e[0m\r\n"
      finish(1)
    rescue StandardError => error
      output "\r\n\e[31mKamal Web error: #{error.class}: #{error.message}\e[0m\r\n"
      finish(1)
      Rails.error.report(error)
    ensure
      agent&.stop
    end

    def spawn(env, directory)
      command = @command || [ *ProcessEnvironment.kamal_command, *@session.arguments ]
      output "\e[2m$ kamal #{@session.arguments.join(" ")}\e[0m\r\n" unless @command
      exit_code = nil

      PTY.spawn(env, *command, chdir: directory.to_s, unsetenv_others: true) do |reader, writer, pid|
        @reader, @writer, @pid = reader, writer, pid
        reader.winsize = @size

        loop do
          if reader.wait_readable(READ_TIMEOUT)
            @last_activity = monotonic
            output reader.readpartial(16.kilobytes)
          elsif monotonic - @last_activity > IDLE_TIMEOUT
            output "\r\n\e[33mClosed after #{IDLE_TIMEOUT.inspect} without activity.\e[0m\r\n"
            signal("TERM")
          end
        rescue EOFError, Errno::EIO
          break
        end

        _, status = Process.wait2(pid)
        exit_code = status.exitstatus
      ensure
        @writer = @reader = @pid = nil
      end

      exit_code
    end

    def finish(exit_code)
      @on_exit.call(exit_code)
    end

    def output(data)
      @on_output.call(data.b)
    end

    def signal(name)
      Process.kill("-#{name}", @pid) if @pid
    rescue Errno::ESRCH, Errno::EPERM
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
