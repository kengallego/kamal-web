require "rails_helper"

RSpec.describe "Breadcrumb navigation" do
  let(:project) { create(:project) }

  before { sign_in }

  def breadcrumb_items
    Nokogiri::HTML(response.body).css('nav[aria-label="Breadcrumbs"] li')
  end

  it "links back to the dashboard and project from a project view" do
    get project_monitoring_path(project)

    expect(response).to have_http_status(:ok)
    items = breadcrumb_items
    expect(items.map { |item| item.text.delete("/").strip }).to eq([ "Dashboard", project.name, "Monitoring" ])
    expect(items[0].at_css("a")["href"]).to eq(root_path)
    expect(items[1].at_css("a")["href"]).to eq(project_path(project))
    expect(items.last.at_css('[aria-current="page"]').text).to eq("Monitoring")
    expect(items.last.at_css("a")).to be_nil
  end

  it "keeps the activity list in the path to command output" do
    run = project.command_runs.create!(kind: "version")
    get project_command_run_path(project, run)

    expect(response).to have_http_status(:ok)
    links = breadcrumb_items.css("a")
    expect(links.map { |link| link["href"] }).to eq([ root_path, project_path(project), project_command_runs_path(project) ])
    expect(breadcrumb_items.last.at_css('[aria-current="page"]').text).to eq(run.command.label)
  end

  it "shows the parent for settings without repeating a trail on the dashboard" do
    get edit_settings_path
    expect(breadcrumb_items.first.at_css("a")["href"]).to eq(root_path)
    expect(breadcrumb_items.last.at_css('[aria-current="page"]').text).to eq("Settings")

    get root_path
    expect(breadcrumb_items).to be_empty
  end
end
