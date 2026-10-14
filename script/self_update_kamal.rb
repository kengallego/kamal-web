# Runs Kamal for SelfUpdate, which deploys Kamal Web from the server it runs
# on. Kamal's local registry (localhost:5555) runs on the server's Docker
# there, so the server already reaches it. The SSH tunnel Kamal opens to the
# server for it would bind that same port on the same machine and fail.
require "kamal"

Kamal::Cli::Build::PortForwarding.prepend(Module.new do
  def forward
    yield
  end
end)

load Gem.bin_path("kamal", "kamal")
