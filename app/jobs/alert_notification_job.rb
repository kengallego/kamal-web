# Posts an alert that opened or resolved to the project's webhook.
class AlertNotificationJob < ApplicationJob
  queue_as :default

  retry_on(*NotificationWebhook::ERRORS, wait: 30.seconds, attempts: 3)
  discard_on ActiveJob::DeserializationError

  def perform(alert, event)
    NotificationWebhook.deliver(alert.project, payload(alert, event))
  end

  def payload(alert, event)
    I18n.with_locale(:en) do
      NotificationWebhook.payload alert.project, text: summary(alert, event), json: {
        event: "alert.#{event}",
        project: alert.project.name,
        kind: alert.kind,
        subject: alert.subject,
        title: alert.title,
        message: alert.message,
        opened_at: alert.opened_at.iso8601,
        resolved_at: alert.resolved_at&.iso8601,
        url: NotificationWebhook.url("/projects/#{alert.project_id}")
      }
    end
  end

  private
    def summary(alert, event)
      if event == "resolved"
        "✅ Resolved for #{alert.project.name}: #{alert.title} (after #{ActiveSupport::Duration.build((alert.resolved_at - alert.opened_at).round).inspect})"
      else
        "🚨 #{alert.project.name}: #{alert.title}#{" (#{alert.message})" if alert.message.present?}"
      end
    end
end
