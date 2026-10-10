require "rails_helper"

RSpec.describe ConsoleProcess do
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
  let(:session) { project.console_sessions.create!(kind: "rails") }
  let(:output) { Queue.new }
  let(:exits) { Queue.new }

  def start(command)
    described_class.new(session, command: command, on_output: ->(data) { output << data }, on_exit: ->(code) { exits << code }).tap(&:start)
  end

  def read_until(text)
    buffer = +""
    Timeout.timeout(5) { buffer << output.pop until buffer.include?(text) }
    buffer
  end

  it "pipes input and output through a PTY sized like the browser terminal" do
    process = start([ "sh", "-c", "stty size; read line; echo got:$line; exit 3" ])
    process.resize(30, 100)

    expect(read_until("30 100")).to include("30 100")
    process.write("hello\n")
    expect(read_until("got:hello")).to include("got:hello")
    expect(Timeout.timeout(5) { exits.pop }).to eq(3)
  end

  it "kills the process when stopped" do
    process = start([ "sh", "-c", "echo ready; sleep 60" ])
    read_until("ready")

    process.stop

    expect(process).not_to be_running
  end
end
