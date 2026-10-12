# Posts the result of a finished operation to the project's webhook.
class DeployNotificationJob < ApplicationJob
  queue_as :default

  retry_on(*NotificationWebhook::ERRORS, wait: 30.seconds, attempts: 3)
  discard_on ActiveJob::DeserializationError

  def perform(run)
    NotificationWebhook.deliver(run.project, payload(run))
  end

  def payload(run)
    NotificationWebhook.payload run.project, text: summary(run), json: {
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

  private
    def summary(run)
      icon = { "succeeded" => "✅", "failed" => "❌", "canceled" => "⚪" }.fetch(run.status, "•")
      target = [ run.project.name, run.destination ].compact.join(" / ")
      revision = run.git_revision ? " (#{run.git_revision.first(7)})" : ""
      link = run_url(run) ? "\n#{run_url(run)}" : ""
      "#{icon} #{run.command.label} #{run.status} for #{target}#{revision}#{" (deploy webhook)" if run.trigger == "webhook"}#{link}"
    end

    def run_url(run)
      NotificationWebhook.url("/projects/#{run.project_id}/command_runs/#{run.id}")
    end
end
