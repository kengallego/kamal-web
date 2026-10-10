require "net/http"

# Posts the result of a finished operation to the project's webhook, formatted
# for Slack, Discord or as plain JSON.
class DeployNotificationJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(run)
    url = run.project.notification_webhook_url
    return if url.blank?

    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "User-Agent" => "KamalWeb")
    request.body = payload(run).to_json

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  def payload(run)
    case run.project.notification_format
    when "slack" then { text: summary(run) }
    when "discord" then { content: summary(run) }
    else
      {
        event: "command_run.finished",
        project: run.project.name,
        destination: run.destination,
        command: run.kind,
        status: run.status,
        exit_code: run.exit_code,
        git_revision: run.git_revision,
        triggered_by: run.triggered_by,
        duration_seconds: run.duration&.round,
        url: run_url(run)
      }
    end
  end

  private
    def summary(run)
      icon = { "succeeded" => "✅", "failed" => "❌", "canceled" => "⚪" }.fetch(run.status, "•")
      target = [ run.project.name, run.destination ].compact.join(" / ")
      revision = run.git_revision ? " (#{run.git_revision.first(7)})" : ""
      link = run_url(run) ? "\n#{run_url(run)}" : ""
      "#{icon} #{run.command.label} #{run.status} for #{target}#{revision}#{" (deploy webhook)" if run.trigger == "webhook"}#{link}"
    end

    def run_url(run)
      host = ENV["KAMAL_WEB_URL"].presence
      "#{host.chomp("/")}/projects/#{run.project_id}/command_runs/#{run.id}" if host
    end
end
