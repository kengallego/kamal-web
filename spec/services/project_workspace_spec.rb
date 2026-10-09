require "rails_helper"

RSpec.describe ProjectWorkspace do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def local_project
    path = create_sample_project_directory(File.join(@root, "demo"))
    allow(Rails.configuration.x).to receive(:projects_path).and_return(Pathname.new(@root))
    create(:project, source_kind: "local", local_path: path, repository_url: nil, config_snapshots: {})
  end

  it "reads every destination's config with the project's variables" do
    project = local_project
    project.environment_variables.create!(key: "STAGING_HOST", value: "st.example.com", destination: "staging")

    described_class.new(project).sync!

    project.reload
    expect(project.destinations).to eq([ nil, "staging" ])
    expect(project.config_for(nil).roles).to eq("web" => [ "192.0.2.10" ])
    expect(project.config_for("staging").proxy_hosts).to eq([ "st.example.com" ])
    expect(project.config_for("staging").accessories).to eq("db" => [ "192.0.2.12" ])
    expect(project.sync_error).to be_nil
  end

  it "stores config errors per destination" do
    project = local_project
    File.write(File.join(project.local_path, "config/deploy.yml"), "service: [")

    described_class.new(project).sync!

    expect(project.reload.config_for(nil).error).to be_present
  end

  it "writes secret files into the workspace" do
    project = local_project
    project.project_files.create!(path: "config/master.key", content: "abc123")

    described_class.new(project).sync!

    key = File.join(project.local_path, "config/master.key")
    expect(File.read(key)).to eq("abc123")
    expect(File.stat(key).mode & 0o777).to eq(0o600)
  end

  it "clones and updates git projects" do
    source = create_sample_project_directory(File.join(@root, "source"))
    system("git", "-C", source, "init", "-q", "-b", "main", exception: true)
    system("git", "-C", source, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qam", "init", "--allow-empty", exception: true)
    system("git", "-C", source, "add", ".", exception: true)
    system("git", "-C", source, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "config", exception: true)

    allow(Rails.configuration.x).to receive(:workspaces_path).and_return(Pathname.new(File.join(@root, "workspaces")))
    project = create(:project, config_snapshots: {})
    project.update_column(:repository_url, "file://#{source}")

    described_class.new(project).sync!
    first_revision = project.reload.git_revision
    expect(project.workspace_path.join("config/deploy.yml")).to exist
    expect(project.destinations).to eq([ nil, "staging" ])

    File.write(File.join(source, "NEW"), "x")
    system("git", "-C", source, "add", ".", exception: true)
    system("git", "-C", source, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "more", exception: true)

    described_class.new(project).sync!
    expect(project.reload.git_revision).not_to eq(first_revision)
    expect(project.workspace_path.join("NEW")).to exist
  end

  it "reports git failures without leaking the access token" do
    allow(Rails.configuration.x).to receive(:workspaces_path).and_return(Pathname.new(File.join(@root, "workspaces")))
    project = create(:project, repository_url: "https://127.0.0.1:9/acme/demo.git", git_access_token: "supersecret", config_snapshots: {})

    expect { described_class.new(project).sync! }.to raise_error(ProjectWorkspace::Error) { |error|
      expect(error.message).not_to include("supersecret")
    }
    expect(project.reload.sync_error).to be_present
  end
end
