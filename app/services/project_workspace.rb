require "open3"

# Keeps a project's working copy ready for Kamal: clones or updates git
# projects, writes the project's secret files and reads its deploy config.
class ProjectWorkspace
  class Error < StandardError; end

  attr_reader :project

  def initialize(project, logger: nil)
    @project = project
    @logger = logger || ->(_line) { }
  end

  # Returns the checked-out git revision, if any.
  # Pass sync: false while another operation uses the checkout, so a git reset
  # can't change the code under a running deploy.
  def prepare!(env, sync: true)
    with_lock do
      if project.git? && (sync || !path.join(".git").directory?)
        sync_repository!(env)
      elsif project.git?
        log "Another operation is running; using the current checkout"
      end
      raise Error, "Project directory #{path} does not exist" unless path.directory?

      write_project_files!
      current_revision
    end
  end

  def refresh_config!(env)
    snapshots = discover_destinations.to_h { |destination| [ destination.to_s, dump_config(destination, env) ] }

    # The base config alone is often incomplete when destinations exist.
    if snapshots[""]&.key?("error") && snapshots.except("").values.any? { |snapshot| !snapshot.key?("error") }
      snapshots.delete("")
    end

    project.update_columns(config_snapshots: snapshots, git_revision: current_revision, synced_at: Time.current, sync_error: nil)
  end

  # Full sync used by the "Sync" button and after editing a project.
  def sync!
    SshAgent.with_keys(project.ssh_keys) do |agent_env|
      env = ProcessEnvironment.build(project.environment_for(nil).merge(agent_env))
      prepare!(env, sync: project.active_operation.nil?)
      refresh_config!(env)
    end
  rescue Error, SshAgent::Error => error
    project.update_columns(sync_error: error.message, synced_at: Time.current)
    raise
  end

  def path
    project.workspace_path
  end

  def config_path
    path.join(project.config_file)
  end

  def discover_destinations
    pattern = config_path.sub_ext(".*.yml").to_s
    names = Dir.glob(pattern).map { |file| File.basename(file, ".yml").delete_prefix("#{config_path.basename(".yml")}.") }
    [ nil ] + names.grep(/\A[\w-]+\z/).sort
  end

  private
    def with_lock
      lock_path = Rails.configuration.x.workspaces_path.join("project-#{project.id}.lock")
      FileUtils.mkdir_p(lock_path.dirname)
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def log(line)
      @logger.call(line)
    end

    def sync_repository!(env)
      if path.join(".git").directory?
        log "Fetching #{project.branch} from #{project.repository_url}"
        git! env, "fetch", "--prune", "--depth", "50", authenticated_url, "+refs/heads/#{project.branch}:refs/remotes/origin/#{project.branch}"
        git! env, "reset", "--hard", "origin/#{project.branch}"
        git! env, "clean", "-fd"
      else
        log "Cloning #{project.repository_url} (#{project.branch})"
        FileUtils.rm_rf(path)
        FileUtils.mkdir_p(path.dirname)
        run! env, "git", "clone", "--branch", project.branch, "--single-branch", "--depth", "50", authenticated_url, path.to_s
        git! env, "remote", "set-url", "origin", project.repository_url
      end
    end

    def write_project_files!
      project.project_files.each do |file|
        target = path.join(file.path).expand_path
        raise Error, "Refusing to write #{file.path} outside the project" unless target.to_s.start_with?("#{path.expand_path}/")

        FileUtils.mkdir_p(target.dirname)
        File.write(target, file.content.to_s)
        File.chmod(0o600, target)
      end
    end

    def current_revision
      return unless path.join(".git").exist?

      output, status = Open3.capture2e(ProcessEnvironment.build, "git", "-C", path.to_s, "rev-parse", "HEAD")
      output.strip if status.success?
    end

    def dump_config(destination, env)
      raise Error, "Config file #{project.config_file} not found" unless config_path.file?

      env = env.merge(project.environment_for(destination))
      output, _status = Open3.capture2e(env, *ProcessEnvironment.ruby_command("script/kamal_config_dump.rb"),
        project.config_file, destination.to_s, chdir: path.to_s)
      JSON.parse(output.lines.last.to_s)
    rescue JSON::ParserError
      { "error" => output.to_s.strip.last(2000) }
    end

    def authenticated_url
      return project.repository_url unless project.git_access_token.present? && project.repository_url.start_with?("https://")

      uri = URI.parse(project.repository_url)
      uri.user = uri.user.presence || "x-access-token"
      uri.password = project.git_access_token
      uri.to_s
    end

    def git!(env, *args)
      run! env, "git", "-C", path.to_s, *args
    end

    def run!(env, *command)
      output, status = Open3.capture2e(env, *command)
      raise Error, "#{redact(command.join(" "))} failed:\n#{redact(output)}" unless status.success?
      output
    end

    def redact(text)
      token = project.git_access_token
      token.present? ? text.gsub(token, "[token]") : text
    end
end
