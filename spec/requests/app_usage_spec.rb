require "rails_helper"

RSpec.describe "App resource usage" do
  it "keeps the app and total usage paired on the busiest app host in the dashboard" do
    sign_in
    project = create(:project, config_snapshots: { "" => { "service" => "demo", "roles" => { "web" => %w[ 192.0.2.10 192.0.2.20 ] } } })
    project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current, app_cpu_percent: 20, cpu_percent: 40)
    project.server_metrics.create!(host: "192.0.2.20", collected_at: Time.current, app_cpu_percent: 5, cpu_percent: 90)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("App: 20% · Machine: 40%")
    expect(response.body).not_to include("App: 20% · Machine: 90%")
  end

  it "shows the app against machine capacity even when the selected historical range has no samples" do
    sign_in
    project = create(:project)
    project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current, cpu_percent: 60, app_cpu_percent: 15,
      memory_total: 8000, memory_used: 4000, app_memory_used: 1000, disk_total: 10000, disk_used: 7000, app_disk_used: 1000)
    get project_monitoring_path(project, range: "7d")
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Machine total:", "Whole machine")
    totals = Nokogiri::HTML(response.body).css("span.text-success\\/50").map(&:text)
    expect(totals).to include("60%", "50%", "70%")
    expect(response.body).to include('class="meter-app" style="width: 15.0%"')
  end

  it "shows host shading without inventing app usage for old samples" do
    sign_in
    project = create(:project)
    project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current, cpu_percent: 60)
    get project_monitoring_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="meter-total" style="width: 60.0%"')
    expect(response.body).not_to include('class="meter-app"')
  end
end
