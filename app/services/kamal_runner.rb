require "pty"

# Executes one CommandRun: prepares the workspace, spawns Kamal in a PTY so its
# output streams line by line, and records the result.
class KamalRunner
  FLUSH_INTERVAL = 0.5

  def initialize(run)
    @run = run
    @project = run.project
  end

  def call
    return if @run.canceled?

    @run.start!
    log "$ #{@run.display_command}\n"

    SshAgent.with_keys(@project.ssh_keys) do |agent_env|
      env = ProcessEnvironment.build(@project.environment_for(@run.destination).merge(agent_env))
      workspace = ProjectWorkspace.new(@project, logger: ->(line) { log "#{line}\n" })
      other_operation = @project.active_operation
      revision = workspace.prepare!(env, sync: other_operation.nil? || other_operation == @run)
      @run.update!(git_revision: revision) if revision

      exit_code = spawn(env, workspace.path)
      @run.finish!(exit_code)
      workspace.refresh_config!(env) if @run.succeeded_deploy?
    end
  rescue ProjectWorkspace::Error, SshAgent::Error => error
    @run.fail!(error.message)
  rescue StandardError => error
    @run.fail!("Kamal UI error: #{error.class}: #{error.message}")
    raise
  end

  private
    def spawn(env, directory)
      buffer = +""
      last_flush = monotonic
      exit_code = nil
      deadline = monotonic + CommandRun::FOLLOW_LIMIT if @run.follow?
      timed_out = false

      PTY.spawn(env, *ProcessEnvironment.kamal_command, *@run.arguments, chdir: directory.to_s, unsetenv_others: true) do |reader, writer, pid|
        writer.close
        @run.update!(pid: pid)

        loop do
          if reader.wait_readable(FLUSH_INTERVAL)
            buffer << reader.readpartial(16.kilobytes)
          end

          if buffer.present? && monotonic - last_flush >= FLUSH_INTERVAL
            log buffer
            buffer = +""
            last_flush = monotonic
          end

          if deadline && !timed_out && monotonic > deadline
            timed_out = true
            buffer << "\nStopped following after #{CommandRun::FOLLOW_LIMIT.inspect}.\n"
            Process.kill("-TERM", pid) rescue Errno::ESRCH
          end
        rescue EOFError, Errno::EIO
          break
        end

        log buffer if buffer.present?
        _, status = Process.wait2(pid)
        exit_code = timed_out ? 0 : status.exitstatus || 1
      end

      exit_code || 1
    end

    def log(text)
      @run.append_output(text)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
