require "open3"

# Deploys a newer Kamal Web release over this instance, with Kamal, when
# Settings → Update automatically is on (or Update now is pressed).
#
# Kamal stops the old container at the end of a deploy, so the deploy can't
# run in this one: #launch starts a helper container from the current image,
# with the same volume, network and Docker socket, which runs #perform.
#
# Releases publish their image to GitHub's registry (see
# .github/workflows/release.yml), so nothing is built here. Before anything is
# pulled, #perform checks the release's signature with cosign against
# SIGNING_KEY, the public key shipped in this image. The maintainer signs each
# release on their own machine (bin/sign-release), never in CI, so taking over
# the GitHub account or the registry isn't enough to get code onto this server.
# The signature names the tag, so an older signed image can't be passed off as
# a newer release.
#
# The image is then pulled by the digest that was verified, handed to the
# registry Kamal runs on this server and deployed with `kamal deploy
# --skip-push`, so kamal-proxy switches over without downtime and Kamal can
# still roll back. The release's config/deploy.yml and .kamal hooks come out of
# that same verified image. Kamal reaches this server over SSH with Kamal Web's
# own key (the one `kamal authorize` let in), with the settings Kamal Web was
# deployed with standing in for .env.
class SelfUpdate
  class Error < StandardError; end
  # The release has no valid signature from SIGNING_KEY, or not yet.
  class Unverified < Error; end

  CONTAINER = "kamal-web-self-update".freeze
  STORAGE = "/rails/storage".freeze
  DOCKER_SOCKET = "/var/run/docker.sock".freeze
  # Runs Kamal without its registry tunnel, see the script.
  LAUNCHER = "script/self_update_kamal.rb".freeze
  RELEASE_IMAGE = "ghcr.io/#{KamalWeb::REPOSITORY}".freeze
  # The image and registry in config/deploy.yml.
  KAMAL_IMAGE = "localhost:5555/kamal-web".freeze
  # What config/deploy.yml reads from .env and Kamal Web gets as env vars.
  DEPLOY_SETTINGS = %w[ KAMAL_WEB_PASSWORD KAMAL_WEB_TOTP_SECRET KAMAL_WEB_ALLOWED_IPS KAMAL_WEB_SSH_USER KAMAL_WEB_SSH_HOST_KEYS ].freeze
  # Also passed to the helper, which needs them to find this server.
  HELPER_SETTINGS = (DEPLOY_SETTINGS + %w[ KAMAL_WEB_URL KAMAL_WEB_HOST_ADDRESS ]).freeze
  OUTPUT_LIMIT = 100.kilobytes
  SIGNING_KEY = Rails.root.join("config/release-signing.pub")
  # Where the release image keeps the config Kamal deploys it with.
  RELEASE_CONFIG = %w[ /rails/config/deploy.yml /rails/.kamal ].freeze

  def initialize(docker: LocalDocker.new)
    @docker = docker
  end

  # Why this instance can't update itself, as [ key, interpolations ], or nil.
  def problem
    container = own_container
    return [ :not_deployed, {} ] unless container && ENV["KAMAL_WEB_URL"].present?
    return [ :no_signing_key, {} ] unless SIGNING_KEY.file?

    # The release's config/deploy.yml only mounts these. Anything else was
    # added by hand and would be lost.
    extra = container.fetch("Mounts", []).map { |mount| mount["Destination"] } - [ STORAGE, DOCKER_SOCKET ]
    [ :custom_volumes, { paths: extra.sort.to_sentence } ] if extra.any?
  end

  # Starts the helper container that deploys +tag+. Returns false when it couldn't.
  def launch(tag)
    return false if problem

    container = own_container
    setting = Setting.instance
    setting.update!(auto_update_version: tag.delete_prefix("v"), auto_update_status: "running", auto_update_started_at: Time.current, auto_update_finished_at: nil, auto_update_output: nil)

    @docker.start_container(
      "--rm", "--name", CONTAINER,
      "--network", container.dig("NetworkSettings", "Networks").keys.first,
      "--volume", "#{storage_source(container)}:#{STORAGE}",
      "--volume", "#{DOCKER_SOCKET}:#{DOCKER_SOCKET}",
      *HELPER_SETTINGS.select { |name| ENV[name] }.flat_map { |name| [ "--env", name ] },
      container.dig("Config", "Image"),
      "./bin/rails", "kamal_web:self_update[#{tag}]",
      env: ENV.slice(*HELPER_SETTINGS)
    )
    true
  rescue LocalDocker::Error => error
    finish(setting, "failed", error.message)
    false
  end

  # Runs in the helper container.
  def perform(tag)
    setting = Setting.instance
    output = +""

    kamal = ProcessEnvironment.ruby_command(LAUNCHER)

    Dir.mktmpdir("kamal-web-update") do |dir|
      SshAgent.with_keys(setting.ssh_private_key) do |agent_env|
        env = ProcessEnvironment.build(deploy_settings.merge(agent_env))
        image = "#{RELEASE_IMAGE}@#{verified_digest(output, env, tag)}"
        execute(output, env, "docker", "pull", "--quiet", image)
        copy_release_config(output, env, image, dir)
        execute(output, env, "docker", "tag", image, "#{KAMAL_IMAGE}:#{tag}")
        execute(output, env, *kamal, "registry", "setup", chdir: dir)
        execute(output, env, "docker", "push", "--quiet", "#{KAMAL_IMAGE}:#{tag}")
        execute(output, env, *kamal, "deploy", "--skip-push", "--version", tag, chdir: dir)
      end
    end
    finish(setting, "succeeded", output)
  rescue Unverified => error
    finish(setting, "unsigned", output << error.message)
  rescue Error, SshAgent::Error => error
    finish(setting, "failed", output << error.message)
  end

  private
    def own_container
      name = ENV["KAMAL_CONTAINER_NAME"].presence
      @own_container ||= @docker.container(name) if name
    end

    def storage_source(container)
      mount = container.fetch("Mounts").find { |mount| mount["Destination"] == STORAGE }
      mount["Type"] == "volume" ? mount["Name"] : mount["Source"]
    end

    # Stands in for the .env config/deploy.yml loads. The server is reached
    # the way detected apps are, at the container's gateway.
    def deploy_settings
      ENV.slice(*DEPLOY_SETTINGS).merge(
        "KAMAL_WEB_SERVER" => KamalDiscovery.host_address,
        "KAMAL_WEB_HOST" => URI(ENV.fetch("KAMAL_WEB_URL")).host
      )
    end

    # The digest of the image the signature covers, for the release's tag.
    def verified_digest(output, env, tag)
      stdout, stderr, status = Open3.capture3(env, "cosign", "verify", "--key", SIGNING_KEY.to_s, "--annotations", "tag=#{tag}", "--output", "json", "#{RELEASE_IMAGE}:#{tag}", unsetenv_others: true)
      output << stderr
      raise Unverified, "#{RELEASE_IMAGE}:#{tag} has no valid signature" unless status.success?

      digests = JSON.parse(stdout).map { |signature| signature.dig("critical", "image", "docker-manifest-digest") }.uniq
      raise Unverified, "Unexpected cosign output" unless digests.one? && digests.first.to_s.match?(/\Asha256:\h{64}\z/)

      output << "Verified #{RELEASE_IMAGE}:#{tag} (#{digests.first})\n"
      digests.first
    rescue JSON::ParserError, NoMethodError
      raise Unverified, "Unexpected cosign output"
    rescue Errno::ENOENT
      raise Unverified, "cosign is not installed"
    end

    def copy_release_config(output, env, image, dir)
      container = execute(output, env, "docker", "create", "--quiet", image).lines.last.to_s.strip
      FileUtils.mkdir_p(File.join(dir, "config"))
      RELEASE_CONFIG.each do |path|
        execute(output, env, "docker", "cp", "#{container}:#{path}", File.join(dir, path.delete_prefix("/rails/")))
      end
      # Kamal expects to run in a git checkout.
      execute(output, env, "git", "init", "--quiet", chdir: dir)
    ensure
      Open3.capture2e(env, "docker", "rm", container, unsetenv_others: true) if container.present?
    end

    def execute(output, env, *command, chdir: Dir.pwd)
      result, status = Open3.capture2e(env, *command, chdir: chdir, unsetenv_others: true)
      output << result
      raise Error, "#{command.last(2).join(" ")} failed" unless status.success?

      result
    end

    def finish(setting, status, output)
      setting.update!(auto_update_status: status, auto_update_finished_at: Time.current, auto_update_output: output.to_s.last(OUTPUT_LIMIT))
    end
end
