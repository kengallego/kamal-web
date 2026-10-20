# What someone did, recorded by Auditing for every change made from the
# dashboard and by the deploy webhook. Never edited; only read on the Activity page.
class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :project, optional: true

  scope :latest_first, -> { order(id: :desc) }

  def self.record(action, actor: Current.user&.label, user: Current.user, project: nil, subject: nil, **details)
    create!(action: action, actor: actor || "?", user: user, project: project,
      subject_type: subject&.class&.name, subject_id: subject&.id, details: details.compact, ip_address: Current.ip_address)
  end

  def label
    I18n.t("audit_events.actions.#{action.tr("/#", "__")}", default: action)
  end
end
