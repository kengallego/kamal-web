require "open3"

# Deploys a newer Kamal Web release over this instance, with Kamal, when
# Settings → Update automatically is on (or Update now is pressed).
#
# Kamal stops the old container at the end of a deploy, so the deploy can't
# run in this one: #launch starts a helper container from the current image,
# with the same volume, network and Docker socket, which runs #perform.
#
# Releases publish their image to GitHub's registry (see
# .github/workflows/release.yml), so nothing is built here: #perform pulls it,
# hands it to the registry Kamal runs on this server and deploys it with
# `kamal deploy --skip-push`, so kamal-proxy switches over without downtime and
# Kamal can still roll back. Kamal reaches this server over SSH with Kamal
# Web's own key (the one `kamal authorize` let in), with the release's config
# and the settings Kamal Web was deployed with standing in for .env.
class SelfUpdate
  class Error < StandardError; end

  CONTAINER = "kamal-web-self-update".freeze
  STORAGE = "/rails/storage".freeze
  DOCKER_SOCKET = "/var/run/docker.sock".freeze
  # Runs Kamal without its registry tunnel, see the script.
  LAUNCHER = "script/self_update_kamal.rb".freeze
  RELEASE_IMAGE = "ghcr.io/#{KamalWeb::REPOSITORY}".freeze
  # The image and registry in config/deploy.yml.
  KAMAL_IMAGE = "localhost:5555/kamal-web".freeze
  # What config/deploy.yml reads from .env and Kamal Web gets as env vars.
  DEPLOY_SETTINGS = %w[ KAMAL_WEB_PASSWORD KAMAL_WEB_TOTP_SECRET KAMAL_WEB_ALLOWED_IPS KAMAL_WEB_SSH_USER ].freeze
  # Also passed to the helper, which needs them to find this server.
  HELPER_SETTINGS = (DEPLOY_SETTINGS + %w[ KAMAL_WEB_URL KAMAL_WEB_HOST_ADDRESS ]).freeze
  OUTPUT_LIMIT = 100.kilobytes

  def initialize(docker: LocalDocker.new)
    @docker = docker
  end

  # Why this instance can't update itself, as [ key, interpolations ], or nil.
  def problem
    container = own_container
    return [ :not_deployed, {} ] unless container && ENV["KAMAL_WEB_URL"].present?

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
        # Only for config/deploy.yml and .kamal: the code comes in the image.
        execute(output, env, "git", "clone", "--quiet", "--depth", "1", "--branch", tag, "https://github.com/#{KamalWeb::REPOSITORY}.git", dir)
        execute(output, env, "docker", "pull", "--quiet", "#{RELEASE_IMAGE}:#{tag}")
        execute(output, env, "docker", "tag", "#{RELEASE_IMAGE}:#{tag}", "#{KAMAL_IMAGE}:#{tag}")
        execute(output, env, *kamal, "registry", "setup", chdir: dir)
        execute(output, env, "docker", "push", "--quiet", "#{KAMAL_IMAGE}:#{tag}")
        execute(output, env, *kamal, "deploy", "--skip-push", "--version", tag, chdir: dir)
      end
    end
    finish(setting, "succeeded", output)
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

    def execute(output, env, *command, chdir: Dir.pwd)
      result, status = Open3.capture2e(env, *command, chdir: chdir, unsetenv_others: true)
      output << result
      raise Error, "#{command.last(2).join(" ")} failed" unless status.success?
    end

    def finish(setting, status, output)
      setting.update!(auto_update_status: status, auto_update_finished_at: Time.current, auto_update_output: output.to_s.last(OUTPUT_LIMIT))
    end
end
