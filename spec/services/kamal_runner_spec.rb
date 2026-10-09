require "rails_helper"

RSpec.describe KamalRunner do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  let(:project) do
    path = create_sample_project_directory(File.join(@root, "demo"))
    allow(Rails.configuration.x).to receive(:projects_path).and_return(Pathname.new(@root))
    create(:project, source_kind: "local", local_path: path, repository_url: nil, config_snapshots: { "" => {} })
  end

  it "runs Kamal and streams its output into the run" do
    run = project.command_runs.create!(kind: "version", user: create(:user))

    described_class.new(run).call

    run.reload
    expect(run.status).to eq("succeeded")
    expect(run.exit_code).to eq(0)
    expect(run.output).to include("$ kamal version", Gem.loaded_specs["kamal"].version.to_s)
  end

  it "records failures" do
    File.write(File.join(project.local_path, "config/deploy.yml"), "service: [")
    run = project.command_runs.create!(kind: "app_details", user: create(:user))

    described_class.new(run).call

    expect(run.reload.status).to eq("failed")
    expect(run.exit_code).not_to eq(0)
  end

  it "does not pass instance secrets to Kamal" do
    environment = ProcessEnvironment.build("PROJECT_VAR" => "1")

    expect(environment).to include("PROJECT_VAR" => "1")
    expect(environment.keys).not_to include("SECRET_KEY_BASE", "ADMIN_PASSWORD")
  end

  it "skips runs canceled before they started" do
    run = project.command_runs.create!(kind: "version", user: create(:user))
    run.cancel!

    described_class.new(run).call

    expect(run.reload.output).to be_empty
  end
end
