# Prints the merged Kamal configuration for one destination as JSON.
# Runs in a separate process because rendering deploy.yml evaluates ERB that
# reads ENV, and the project's variables must not leak into the web process.
#
#   ruby script/kamal_config_dump.rb config/deploy.yml [destination]
require "kamal"
require "json"
require "pathname"

config_file, destination = ARGV
destination = nil if destination.to_s.empty?

begin
  config = Kamal::Configuration.create_from(config_file: Pathname.new(config_file), destination: destination, version: "kamal-web")

  proxy_hosts = config.roles.select(&:running_proxy?).flat_map { |role| Array(role.proxy.hosts) }
  ssh_proxy = config.ssh.proxy

  puts JSON.generate(
    service: config.service,
    image: config.repository,
    primary_host: config.primary_host,
    roles: config.roles.to_h { |role| [ role.name, role.hosts ] },
    accessories: config.accessories.to_h { |accessory| [ accessory.name, accessory.hosts ] },
    proxy_hosts: proxy_hosts.compact.uniq,
    ssh: {
      user: config.ssh.user,
      port: config.ssh.port,
      proxy: ssh_proxy.respond_to?(:jump_proxies) ? ssh_proxy.jump_proxies : ssh_proxy&.class&.name
    },
    builder: { arches: config.builder.arches, remote: config.builder.remote, local: config.builder.local? },
    raw: JSON.parse(JSON.generate(config.raw_config.to_h))
  )
rescue StandardError, SyntaxError => error
  puts JSON.generate(error: "#{error.class}: #{error.message}")
end
