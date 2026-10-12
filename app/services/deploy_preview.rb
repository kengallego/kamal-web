require "open3"
require "shellwords"

# What a deploy would change, shown next to the Deploy button: whether Kamal's
# deploy lock is held, and the commits between the version running on the
# server and the project's checkout from the last sync.
class DeployPreview
  Lock = Data.define(:details)
  Commit = Data.define(:sha, :author, :time, :subject)

  SEPARATOR = "--kamal-web--".freeze
  COMMIT_LIMIT = 50

  attr_reader :lock, :deployed_version, :commits

  def initialize(project, destination)
    @project = project
    @destination = destination
    @config = project.config_for(destination)
    @releases = ServerReleases.new(project, destination)
  end

  def call
    return self if @releases.host.blank?

    output = RemoteShell.new(@project, @releases.host, destination: @destination).run("#{lock_command}; echo #{SEPARATOR}; #{@releases.command}")
    lock_output, releases_output = output.split("#{SEPARATOR}\n", 2)
    @lock = parse_lock(lock_output)
    @deployed_version = @releases.parse(releases_output).find(&:current)&.version
    @commits = commits_since(@deployed_version) if @project.git?
    self
  end

  # :none (nothing deployed yet), :current, :ahead (commits to deploy),
  # :unknown (the running version isn't in the checkout's history).
  def state
    if deployed_version.nil? then :none
    elsif commits.nil? then :unknown
    elsif commits.empty? then :current
    else :ahead
    end
  end

  def lock_command
    name = [ "lock", @config.service, @destination.presence ].compact.join("-")
    raise RemoteShell::Error, "Unexpected characters in the Kamal config" unless name.match?(ServerReleases::SAFE)

    # Kamal keeps the lock in the SSH user's home, with base64 details.
    dir = ".kamal/#{name}"
    "if [ -d #{dir} ]; then echo locked; (base64 -d #{dir}/details 2>/dev/null || cat #{dir}/details 2>/dev/null); fi"
  end

  def parse_lock(output)
    lines = output.to_s.lines.map(&:strip)
    Lock.new(details: lines.drop(1).compact_blank.join("\n")) if lines.first == "locked"
  end

  private
    def commits_since(version)
      sha = version.to_s[/\A\h{7,40}/]
      path = @project.workspace_path
      return unless sha && path.join(".git").exist?
      return unless git("cat-file", "-e", "#{sha}^{commit}") && git("merge-base", "--is-ancestor", sha, "HEAD")

      git("log", "--format=%H%x09%an%x09%at%x09%s", "-n", COMMIT_LIMIT.to_s, "#{sha}..HEAD").to_s.lines.map do |line|
        commit, author, time, subject = line.chomp.split("\t", 4)
        Commit.new(sha: commit, author: author, time: Time.zone.at(time.to_i), subject: subject.to_s)
      end
    end

    def git(*args)
      output, status = Open3.capture2e(ProcessEnvironment.build, "git", "-C", @project.workspace_path.to_s, *args)
      output if status.success?
    end
end
