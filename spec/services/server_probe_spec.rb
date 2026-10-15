require "rails_helper"

RSpec.describe ServerProbe do
  let(:probe) { described_class.new(build(:project), "192.0.2.10") }

  def output_with_usage(stats: "ok", sizes: "ok", mounts: "0")
    [ "cpu 100 0 100 800 0", "0.5 0.4 0.3", "4", "8000000000 4000000000",
      "100000000000 50000000000", "", "cpu 150 0 150 900 0", stats, sizes, mounts ].join("#{ServerProbe::SEPARATOR}\n")
  end

  it "sums container CPU and memory against host capacity, and counts writable storage" do
    stats = [ { CPUPerc: "150.00%", MemUsage: "1GiB / 2GiB" }, { CPUPerc: "50.00%", MemUsage: "512MiB / 1GiB" } ].map(&:to_json).join("\n") + "\nok"
    sizes = "{\"SizeRw\":1000}\n{\"SizeRw\":2000}\nok"
    expect(probe.parse(output_with_usage(stats: stats, sizes: sizes, mounts: "5000"))).to include(
      app_cpu_percent: 50.0, app_memory_used: 1_610_612_736, app_disk_used: 8000)
  end

  it "distinguishes an empty app from unavailable or old Docker metrics" do
    expect(probe.parse(output_with_usage)).to include(app_cpu_percent: 0.0, app_memory_used: 0, app_disk_used: 0)
    expect(probe.parse(output_with_usage(stats: "", sizes: "", mounts: ""))).not_to have_key(:app_cpu_percent)
    expect(probe.parse(output_with_usage(stats: "", sizes: "", mounts: ""))).not_to have_key(:app_disk_used)
    expect(probe.parse(output_with_usage(mounts: "unavailable"))).not_to have_key(:app_disk_used)
  end

  it "selects exact service labels for the app and its accessories across destinations" do
    project = build(:project, config_snapshots: {
      "" => { "service" => "demo", "accessories" => { "db" => [ "192.0.2.10" ] } },
      "staging" => { "service" => "demo", "accessories" => { "redis" => [ "192.0.2.10" ] },
        "raw" => { "accessories" => { "redis" => { "service" => "custom-cache" } } } }
    })
    script = described_class.new(project, "192.0.2.10").send(:container_script)
    expect(script).to include("--filter label\\=service\\=demo", "--filter label\\=service\\=demo-db", "--filter label\\=service\\=custom-cache")
    expect(script).not_to include("kamal-proxy", "demo-*", "demo-redis")
  end

  it "collects Docker statistics and deduplicates shared mount paths, including paths with spaces" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "docker"), <<~SH)
        #!/bin/sh
        case "$1 $2" in
          'ps -aq'|'ps -q') printf 'first\\nsecond\\n' ;;
          'stats --no-stream') printf '%s\\n' '{"CPUPerc":"200%","MemUsage":"1GiB / 2GiB"}' ;;
          'inspect --size') printf '%s\\n' '{"SizeRw":1000}' '{"SizeRw":2000}' ;;
          'inspect --format') printf '/app data\\n/app data\\n' ;;
          *) exit 1 ;;
        esac
      SH
      File.write(File.join(directory, "du"), "#!/bin/sh\nprintf '40\\t%s\\n' \"$3\"\n")
      File.chmod(0o755, File.join(directory, "docker"), File.join(directory, "du"))
      result, status = Open3.capture2({ "PATH" => "#{directory}:#{ENV.fetch('PATH')}" }, "/bin/sh", "-c", probe.send(:container_script))
      expect(status).to be_success
      attributes = probe.parse(output_with_usage.split("#{ServerProbe::SEPARATOR}\n").first(7).join("#{ServerProbe::SEPARATOR}\n") + "#{ServerProbe::SEPARATOR}\n" + result)
      expect(attributes).to include(app_cpu_percent: 50.0, app_memory_used: 1_073_741_824, app_disk_used: 43_960)
    end
  end

  it "parses the probe output" do
    separator = "#{ServerProbe::SEPARATOR}\n"
    output = [
      "cpu  100 0 100 800 0 0 0 0 0 0\n",
      "0.50 0.40 0.30 1/200 1234\n",
      "2\n",
      "4000000000 1000000000\n",
      "50000000000 25000000000\n",
      %({"Names":"demo-web-abc","Image":"acme/demo:abc","Status":"Up 2 hours","State":"running","Labels":"service=demo,role=web,destination=,traefik.enable=true"}\n),
      "cpu  150 0 150 900 0 0 0 0 0 0\n"
    ].join(separator)

    attributes = described_class.new(build(:project), "192.0.2.10").parse(output)

    expect(attributes).to include(load_1: 0.5, cpu_count: 2, memory_total: 4_000_000_000, memory_used: 1_000_000_000, disk_used: 25_000_000_000)
    expect(attributes[:cpu_percent]).to eq(50.0)
    expect(attributes[:containers].first["Names"]).to eq("demo-web-abc")
    expect(attributes[:containers].first["Labels"]).to eq("service" => "demo", "role" => "web", "destination" => "")
  end
end
