module SampleProjectHelpers
  # Builds a throwaway Kamal project with a base config and a staging destination.
  def create_sample_project_directory(root)
    FileUtils.mkdir_p(File.join(root, "config"))
    FileUtils.mkdir_p(File.join(root, ".kamal"))
    File.write(File.join(root, "config/deploy.yml"), <<~YAML)
      service: demo
      image: acme/demo
      servers:
        web:
          - 192.0.2.10
      proxy:
        host: demo.example.com
      registry:
        username: acme
        password:
          - KAMAL_REGISTRY_PASSWORD
      accessories:
        db:
          image: postgres:16
          host: 192.0.2.12
      builder:
        arch: amd64
    YAML
    File.write(File.join(root, "config/deploy.staging.yml"), <<~YAML)
      servers:
        web:
          - 192.0.2.20
      proxy:
        host: <%= ENV.fetch("STAGING_HOST", "staging.example.com") %>
    YAML
    File.write(File.join(root, ".kamal/secrets"), "KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD\n")
    root
  end
end

RSpec.configure do |config|
  config.include SampleProjectHelpers
end
