# Every Kamal command the UI can run. Arguments are always built as arrays and
# executed without a shell, so user-provided options can't inject commands.
class CommandCatalog
  Command = Data.define(:key, :label, :group, :role, :mutating, :fields, :builder, :description) do
    def arguments(options = {})
      builder.call(options.to_h.stringify_keys.transform_values { |value| value.to_s.strip })
    end

    def mutating?
      mutating
    end
  end

  Field = Data.define(:name, :label, :type, :required, :placeholder)

  GROUPS = {
    "deploy" => "Deploy",
    "app" => "App",
    "proxy" => "Proxy",
    "accessory" => "Accessories",
    "lock" => "Deploy lock",
    "maintenance" => "Maintenance",
    "inspect" => "Inspect"
  }.freeze

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

    def grouped
      all.values.group_by(&:group)
    end

    private
      def command(key, label, group:, role: "viewer", mutating: false, fields: [], description: nil, &builder)
        all[key] = Command.new(key:, label:, group:, role:, mutating:, fields:, builder:, description:)
      end

      def field(name, label, type: :text, required: false, placeholder: nil)
        Field.new(name:, label:, type:, required:, placeholder:)
      end

      def lines(options, default = 200)
        count = options["lines"].to_i
        count = default unless count.between?(1, 5000)
        [ "--lines", count.to_s ]
      end

      def grep(options)
        options["grep"].present? ? [ "--grep", options["grep"] ] : []
      end

      def accessory(options)
        options["name"].presence || "all"
      end
  end

  command "deploy", "Deploy", group: "deploy", role: "deployer", mutating: true,
    description: "Build, push and boot a new version" do
    [ "deploy" ]
  end

  command "redeploy", "Redeploy", group: "deploy", role: "deployer", mutating: true,
    description: "Deploy without bootstrapping servers, proxy or registry login" do
    [ "redeploy" ]
  end

  command "rollback", "Rollback", group: "deploy", role: "deployer", mutating: true,
    fields: [ field("version", "Version", required: true, placeholder: "git sha of a previous deploy") ] do |options|
    raise ArgumentError, "Version is required" if options["version"].blank?
    raise ArgumentError, "Version contains invalid characters" unless options["version"].match?(/\A[\w.\-]+\z/)
    [ "rollback", options["version"] ]
  end

  command "setup", "Setup", group: "deploy", role: "admin", mutating: true,
    description: "Bootstrap servers, boot accessories and deploy" do
    [ "setup" ]
  end

  command "app_boot", "Boot app", group: "app", role: "deployer", mutating: true do
    [ "app", "boot" ]
  end

  command "app_start", "Start app", group: "app", role: "deployer", mutating: true do
    [ "app", "start" ]
  end

  command "app_stop", "Stop app", group: "app", role: "deployer", mutating: true do
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
    fields: [ field("lines", "Lines", type: :number, placeholder: "200"), field("grep", "Filter", placeholder: "text or regex") ] do |options|
    [ "app", "logs" ] + lines(options) + grep(options)
  end

  command "app_exec", "Run command", group: "app", role: "deployer",
    fields: [ field("command", "Command", required: true, placeholder: "bin/rails db:migrate:status") ],
    description: "Runs in a new container from the current image on the primary host" do |options|
    raise ArgumentError, "Command is required" if options["command"].blank?
    [ "app", "exec", "--primary", "--reuse", options["command"] ]
  end

  command "rails_runner", "Rails runner", group: "app", role: "deployer",
    fields: [ field("code", "Ruby code", type: :code, required: true, placeholder: "puts User.count") ],
    description: "Evaluates Ruby with bin/rails runner inside the running app container" do |options|
    raise ArgumentError, "Code is required" if options["code"].blank?
    [ "app", "exec", "--primary", "--reuse", "bin/rails runner #{Shellwords.escape(options["code"])}" ]
  end

  command "app_maintenance", "Maintenance mode", group: "app", role: "deployer", mutating: true do
    [ "app", "maintenance" ]
  end

  command "app_live", "Live mode", group: "app", role: "deployer", mutating: true do
    [ "app", "live" ]
  end

  command "proxy_details", "Proxy details", group: "proxy" do
    [ "proxy", "details" ]
  end

  command "proxy_logs", "Proxy logs", group: "proxy",
    fields: [ field("lines", "Lines", type: :number, placeholder: "200"), field("grep", "Filter") ] do |options|
    [ "proxy", "logs" ] + lines(options) + grep(options)
  end

  command "proxy_boot", "Boot proxy", group: "proxy", role: "admin", mutating: true do
    [ "proxy", "boot" ]
  end

  command "proxy_reboot", "Reboot proxy", group: "proxy", role: "admin", mutating: true do
    [ "proxy", "reboot", "--rolling", "--confirmed" ]
  end

  command "accessory_details", "Accessory details", group: "accessory",
    fields: [ field("name", "Accessory", type: :accessory) ] do |options|
    [ "accessory", "details", accessory(options) ]
  end

  command "accessory_logs", "Accessory logs", group: "accessory",
    fields: [ field("name", "Accessory", type: :accessory, required: true), field("lines", "Lines", type: :number, placeholder: "200"), field("grep", "Filter") ] do |options|
    raise ArgumentError, "Accessory is required" if options["name"].blank?
    [ "accessory", "logs", options["name"] ] + lines(options) + grep(options)
  end

  %w[ boot reboot restart start stop ].each do |action|
    command "accessory_#{action}", "#{action.capitalize} accessory", group: "accessory", role: "admin", mutating: true,
      fields: [ field("name", "Accessory", type: :accessory) ] do |options|
      [ "accessory", action, accessory(options) ] + (action == "reboot" ? [ "--confirmed" ] : [])
    end
  end

  command "lock_status", "Lock status", group: "lock" do
    [ "lock", "status" ]
  end

  command "lock_acquire", "Acquire lock", group: "lock", role: "deployer",
    fields: [ field("message", "Message", required: true, placeholder: "Why deploys are blocked") ] do |options|
    raise ArgumentError, "Message is required" if options["message"].blank?
    [ "lock", "acquire", "--message", options["message"] ]
  end

  command "lock_release", "Release lock", group: "lock", role: "deployer" do
    [ "lock", "release" ]
  end

  command "prune_all", "Prune images and containers", group: "maintenance", role: "deployer", mutating: true do
    [ "prune", "all" ]
  end

  command "registry_login", "Registry login", group: "maintenance", role: "deployer" do
    [ "registry", "login" ]
  end

  command "server_bootstrap", "Bootstrap servers", group: "maintenance", role: "admin", mutating: true,
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
