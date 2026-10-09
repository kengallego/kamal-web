require "rails_helper"

RSpec.describe ProjectFile do
  let(:project) { create(:project) }

  it "accepts relative paths" do
    expect(project.project_files.build(path: "config/master.key")).to be_valid
    expect(project.project_files.build(path: "./.kamal/secrets").tap(&:validate).path).to eq(".kamal/secrets")
  end

  it "rejects paths that escape the project or touch .git" do
    [ "/etc/passwd", "../outside", "config/../../x", ".git/config" ].each do |path|
      expect(project.project_files.build(path: path)).not_to be_valid, path
    end
  end
end
