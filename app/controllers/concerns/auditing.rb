# Records every change made from the dashboard (any request that isn't a
# GET) as an AuditEvent, with who made it, from where, and the ids in its
# path. Parameters are left out, so secrets typed into forms aren't stored.
# Reads worth knowing about, like downloading a backup, call #audit themselves.
module Auditing
  extend ActiveSupport::Concern

  included do
    after_action :audit_change, unless: -> { request.get? || request.head? }
  end

  private
    def audit(action = "#{controller_path}##{action_name}", subject: nil, **details)
      return unless current_user

      project = subject.is_a?(Project) ? subject : (subject.try(:project) || @project)
      AuditEvent.record(action, project: project, subject: subject, **details)
    end

    def audit_change
      return if @audited || response.status >= 400

      ids = request.path_parameters.except(:controller, :action, :format).transform_values(&:to_s)
      subject = audit_subject
      described = %i[ kind destination host key path ].index_with { |name| subject.try(name) if subject.has_attribute?(name) } if subject
      audit(subject: subject, status: response.status, **ids.symbolize_keys, **described.to_h.compact)
    end

    # The record the action was about, when the controller loaded one.
    def audit_subject
      %i[ @run @session @variable @file @server @user @project ]
        .lazy.map { |name| instance_variable_get(name) }.find { |record| record.is_a?(ApplicationRecord) && record.persisted? }
    end
end
