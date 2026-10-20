# Builds the environment for child processes (git, kamal, ssh). Starts from an
# allowlist instead of inheriting ENV so instance secrets like SECRET_KEY_BASE
# or KAMAL_WEB_PASSWORD never reach a project's hooks or .kamal/secrets.
module ProcessEnvironment
  INHERITED = %w[
    PATH HOME LANG LC_ALL TZ TERM USER
    GEM_HOME GEM_PATH RUBYLIB RUBYOPT LD_PRELOAD
    DOCKER_HOST DOCKER_CONFIG DOCKER_CERT_PATH DOCKER_TLS_VERIFY BUILDX_CONFIG
    SSL_CERT_FILE SSL_CERT_DIR HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
  ].freeze

  # Bundler.unbundled_env drops every BUNDLE_* variable, but the image needs
  # these to find the installed gems.
  BUNDLER_SETTINGS = %w[ BUNDLE_PATH BUNDLE_DEPLOYMENT BUNDLE_WITHOUT ].freeze

  module_function

  def build(extra = {})
    base = Bundler.unbundled_env.slice(*INHERITED).merge(ENV.slice(*BUNDLER_SETTINGS))
    base.merge(
      "PATH" => [ SshWrapper.directory, base["PATH"] ].compact.join(File::PATH_SEPARATOR),
      "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s,
      "GIT_TERMINAL_PROMPT" => "0",
      # Mounted projects are usually owned by another uid than the app user.
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "safe.directory",
      "GIT_CONFIG_VALUE_0" => "*",
      # Through SshWrapper's ssh, which applies SshHostKeys.
      "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes",
      "TERM" => "dumb",
      "NO_COLOR" => "1"
    ).merge(extra.transform_keys(&:to_s).transform_values(&:to_s))
  end

  def kamal_command
    [ RbConfig.ruby, Rails.root.join("bin/kamal").to_s ]
  end

  def ruby_command(script)
    [ RbConfig.ruby, "-rbundler/setup", Rails.root.join(script).to_s ]
  end
end
