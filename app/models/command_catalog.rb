# Every Kamal command the UI can run. Arguments are always built as arrays and
# executed without a shell, so user-provided options can't inject commands.
class CommandCatalog
  # Labels are English defaults; config/locales translates them under
  # commands.<key>, command_fields.<name> and command_groups.<group>.
  Command = Data.define(:key, :default_label, :group, :mutating, :fields, :builder, :default_description) do
    def label
      I18n.t("commands.#{key}.label", default: default_label)
    end

    def description
      default_description && I18n.t("commands.#{key}.description", default: default_description)
    end

    def arguments(options = {})
      builder.call(options.to_h.stringify_keys.transform_values { |value| value.to_s.strip })
    end

    def mutating?
      mutating
    end
  end

  Field = Data.define(:name, :default_label, :type, :required, :default_placeholder) do
    def label
      I18n.t("command_fields.#{name}.label", default: default_label)
    end

    def placeholder
      default_placeholder && I18n.t("command_fields.#{name}.placeholder", default: default_placeholder)
    end
  end

  def self.group_label(group)
    I18n.t("command_groups.#{group}", default: GROUPS.fetch(group, group))
  end

  GROUPS = {
    "deploy" => "Deploy",
    "app" => "App",
    "proxy" => "Proxy",
    "accessory" => "Accessories",
    "lock" => "Deploy lock",
    "maintenance" => "Maintenance",
    "inspect" => "Inspect"
  }.freeze

  TABBED = %w[ app_logs app_exec rails_runner ].freeze

  class << self
    def all
      @all ||= {}
    end

    def find(key)
      all.fetch(key.to_s) { raise KeyError, "Unknown command #{key}" }
    end

    def exists?(key)
      all.key?(key.to_s)
    end

    # For the commands page. These have their own tabs (Logs and Console), but
    # stay in the catalog so earlier runs can still be shown and run again.
    def grouped
      all.values.reject { |command| command.key.in?(TABBED) }.group_by(&:group)
    end

    private
      def command(key, label, group:, mutating: false, fields: [], description: nil, &builder)
        all[key] = Command.new(key:, default_label: label, group:, mutating:, fields:, builder:, default_description: description)
      end

      def field(name, label, type: :text, required: false, placeholder: nil)
        Field.new(name:, default_label: label, type:, required:, default_placeholder: placeholder)
      end

      def lines(options, default = 200)
        count = options["lines"].to_i
        count = default unless count.between?(1, 5000)
        [ "--lines", count.to_s ]
      end

      # Kamal interpolates --grep into a remote shell command, so anything that
      # could break out of its quotes is rejected.
      def grep(options)
        return [] if options["grep"].blank?
        raise ArgumentError, "Filter can't contain quotes, backslashes, $ or backticks" if options["grep"].match?(/['"`$\\\n]/)

        [ "--grep", options["grep"] ]
      end

      def follow(options)
        options["follow"] == "1" ? [ "--follow" ] : []
      end

      def host(options)
        return [] if options["host"].blank?
        raise ArgumentError, "Host is not valid" unless options["host"].match?(/\A[\w\[\]][\w.:\[\]-]*\z/)

        [ "--hosts", options["host"] ]
      end

      # Also interpolated into a remote shell command by Kamal.
      def container(options)
        return [] if options["container_id"].blank?
        raise ArgumentError, "Container is not valid" unless options["container_id"].match?(/\A\w[\w.-]*\z/)

        [ "--container-id", options["container_id"] ]
      end

      def log_fields(*extra)
        [ *extra, field("lines", "Lines", type: :number, placeholder: "200"), field("grep", "Filter", placeholder: "text or regex"),
          field("follow", "Follow live", type: :boolean) ]
      end

      def accessory(options)
        options["name"].presence || "all"
      end
  end

  command "deploy", "Deploy", group: "deploy", mutating: true,
    description: "Build, push and boot a new version" do
    [ "deploy" ]
  end

  command "redeploy", "Redeploy", group: "deploy", mutating: true,
    description: "Deploy without bootstrapping servers, proxy or registry login" do
    [ "redeploy" ]
  end

  command "rollback", "Rollback", group: "deploy", mutating: true,
    fields: [ field("version", "Version", required: true, placeholder: "git sha of a previous deploy") ] do |options|
    raise ArgumentError, "Version is required" if options["version"].blank?
    raise ArgumentError, "Version contains invalid characters" unless options["version"].match?(/\A[\w.\-]+\z/)
    [ "rollback", options["version"] ]
  end

  command "setup", "Setup", group: "deploy", mutating: true,
    description: "Bootstrap servers, boot accessories and deploy" do
    [ "setup" ]
  end

  command "app_boot", "Boot app", group: "app", mutating: true do
    [ "app", "boot" ]
  end

  command "app_start", "Start app", group: "app", mutating: true do
    [ "app", "start" ]
  end

  command "app_stop", "Stop app", group: "app", mutating: true do
    [ "app", "stop" ]
  end

  command "app_details", "App details", group: "app" do
    [ "app", "details" ]
  end

  command "app_version", "Running version", group: "app" do
    [ "app", "version" ]
  end

  command "app_containers", "App containers", group: "app" do
    [ "app", "containers" ]
  end

  command "app_images", "App images", group: "app" do
    [ "app", "images" ]
  end

  command "app_logs", "App logs", group: "app",
    fields: log_fields(field("host", "Host", type: :host), field("container_id", "Container", placeholder: "current app container")),
    description: "Follow streams new lines from one host (the primary unless you pick one) for up to 30 minutes" do |options|
    [ "app", "logs" ] + host(options) + container(options) + lines(options) + grep(options) + follow(options)
  end

  command "app_exec", "Run command", group: "app",
    fields: [ field("command", "Command", required: true) ] do |options|
    raise ArgumentError, "Command is required" if options["command"].blank?
    [ "app", "exec", "--primary", "--reuse", options["command"] ]
  end

  command "rails_runner", "Rails runner", group: "app",
    fields: [ field("code", "Ruby code", required: true) ] do |options|
    raise ArgumentError, "Code is required" if options["code"].blank?
    [ "app", "exec", "--primary", "--reuse", "bin/rails runner #{Shellwords.escape(options["code"])}" ]
  end

  command "app_maintenance", "Maintenance mode", group: "app", mutating: true do
    [ "app", "maintenance" ]
  end

  command "app_live", "Live mode", group: "app", mutating: true do
    [ "app", "live" ]
  end

  command "proxy_details", "Proxy details", group: "proxy" do
    [ "proxy", "details" ]
  end

  command "proxy_logs", "Proxy logs", group: "proxy", fields: log_fields(field("host", "Host", type: :host)) do |options|
    [ "proxy", "logs" ] + host(options) + lines(options) + grep(options) + follow(options)
  end

  command "proxy_boot", "Boot proxy", group: "proxy", mutating: true do
    [ "proxy", "boot" ]
  end

  command "proxy_reboot", "Reboot proxy", group: "proxy", mutating: true do
    [ "proxy", "reboot", "--rolling", "--confirmed" ]
  end

  command "accessory_details", "Accessory details", group: "accessory",
    fields: [ field("name", "Accessory", type: :accessory) ] do |options|
    [ "accessory", "details", accessory(options) ]
  end

  command "accessory_logs", "Accessory logs", group: "accessory",
    fields: log_fields(field("name", "Accessory", type: :accessory, required: true)) do |options|
    raise ArgumentError, "Accessory is required" if options["name"].blank?
    [ "accessory", "logs", options["name"] ] + lines(options) + grep(options) + follow(options)
  end

  %w[ boot reboot restart start stop ].each do |action|
    command "accessory_#{action}", "#{action.capitalize} accessory", group: "accessory", mutating: true,
      fields: [ field("name", "Accessory", type: :accessory) ] do |options|
      [ "accessory", action, accessory(options) ] + (action == "reboot" ? [ "--confirmed" ] : [])
    end
  end

  command "lock_status", "Lock status", group: "lock" do
    [ "lock", "status" ]
  end

  command "lock_acquire", "Acquire lock", group: "lock",
    fields: [ field("message", "Message", required: true, placeholder: "Why deploys are blocked") ] do |options|
    raise ArgumentError, "Message is required" if options["message"].blank?
    [ "lock", "acquire", "--message", options["message"] ]
  end

  command "lock_release", "Release lock", group: "lock" do
    [ "lock", "release" ]
  end

  command "prune_all", "Prune images and containers", group: "maintenance", mutating: true do
    [ "prune", "all" ]
  end

  command "registry_login", "Registry login", group: "maintenance" do
    [ "registry", "login" ]
  end

  command "server_bootstrap", "Bootstrap servers", group: "maintenance", mutating: true,
    description: "Installs curl and Docker on servers that lack them" do
    [ "server", "bootstrap" ]
  end

  command "details", "All containers", group: "inspect" do
    [ "details" ]
  end

  command "audit", "Audit log", group: "inspect" do
    [ "audit" ]
  end

  command "version", "Kamal version", group: "inspect" do
    [ "version" ]
  end
end
