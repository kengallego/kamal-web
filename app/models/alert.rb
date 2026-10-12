# A problem found by monitoring, open until its check passes again. Opening
# and resolving one is posted to the project's notification webhook.
class Alert < ApplicationRecord
  KINDS = %w[ host_unreachable disk memory app_down health_check certificate proxy_errors ].freeze
  RETENTION = 30.days

  belongs_to :project

  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :latest_first, -> { order(opened_at: :desc) }

  after_create_commit -> { notify("opened") }

  # failing: true opens the alert (or keeps it open), false resolves it, nil
  # leaves it as it is, for checks that aren't conclusive yet.
  def self.track(project, kind, subject, failing:, message: nil)
    alert = project.alerts.active.find_by(kind: kind, subject: subject.to_s)

    if failing && alert
      alert.update!(message: message) if message.present? && alert.message != message
    elsif failing
      project.alerts.create!(kind: kind, subject: subject.to_s, message: message, opened_at: Time.current)
    elsif failing == false && alert
      alert.resolve!
    end
  end

  def self.prune!
    resolved.where(resolved_at: ...RETENTION.ago).delete_all
  end

  def title
    I18n.t("alerts.kinds.#{kind}", subject: subject)
  end

  def resolve!
    update!(resolved_at: Time.current)
    notify("resolved")
  end

  private
    def notify(event)
      AlertNotificationJob.perform_later(self, event) if project.notification_webhook_url.present?
    end
end
