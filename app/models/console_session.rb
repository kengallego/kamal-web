# An interactive shell opened from the browser. The record is the audit trail
# (what was opened, where and when); the terminal itself streams over
# ConsoleChannel and is never stored.
class ConsoleSession < ApplicationRecord
  KINDS = {
    "rails" => { label: "Rails console", command: "bin/rails console" },
    "dbconsole" => { label: "Database console", command: "bin/rails dbconsole" },
    "shell" => { label: "Shell", command: "sh -c 'if command -v bash >/dev/null; then exec bash; else exec sh; fi'" }
  }.freeze

  # A session can only be attached once, shortly after it's created, so a
  # leaked or reloaded URL can't reopen a shell.
  CLAIM_WINDOW = 5.minutes

  belongs_to :project
  belongs_to :user, optional: true, default: -> { Current.user }

  normalizes :destination, :host, with: ->(value) { value.presence }

  validates :kind, inclusion: { in: KINDS.keys }
  validate :destination_is_known, on: :create
  validate :host_is_known, on: :create

  scope :latest_first, -> { order(created_at: :desc) }

  def label
    I18n.t("console_kinds.#{kind}", default: KINDS.fetch(kind)[:label])
  end

  def arguments
    args = [ "app", "exec", "--interactive", "--reuse" ]
    args += [ "--hosts", host ] if host
    args << KINDS.fetch(kind)[:command]
    args += [ "-c", project.config_file ] unless project.config_file == "config/deploy.yml"
    destination.present? ? args + [ "-d", destination ] : args
  end

  def claim!
    self.class.where(id: id, started_at: nil).where(created_at: CLAIM_WINDOW.ago..).update_all(started_at: Time.current) == 1
  end

  def finish!(exit_code = nil)
    self.class.where(id: id, ended_at: nil).update_all(ended_at: Time.current, exit_code: exit_code)
  end

  def active?
    started_at.present? && ended_at.nil?
  end

  def duration
    (ended_at || Time.current) - started_at if started_at
  end

  def self.close_stale!
    where(ended_at: nil).update_all(ended_at: Time.current)
  end

  private
    def destination_is_known
      errors.add(:destination, :unknown) unless project.destinations.include?(destination)
    end

    def host_is_known
      if host && !project.config_for(destination).all_hosts.include?(host)
        errors.add(:host, :unknown)
      end
    end
end
