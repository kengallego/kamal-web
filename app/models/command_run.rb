class CommandRun < ApplicationRecord
  STATUSES = %w[ queued running succeeded failed canceled ].freeze
  TRIGGERS = %w[ manual webhook ].freeze
  OUTPUT_LIMIT = 2.megabytes
  FOLLOW_LIMIT = 30.minutes

  belongs_to :project

  normalizes :destination, with: ->(d) { d.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validate :kind_is_known
  validate :arguments_are_valid, on: :create
  validate :destination_is_known, on: :create
  validate :one_operation_at_a_time, on: :create
  validate :project_allows_command, on: :create

  scope :active, -> { where(status: %w[ queued running ]) }
  scope :finished, -> { where(status: %w[ succeeded failed canceled ]) }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :latest_first, -> { order(created_at: :desc) }

  after_create_commit -> { CommandRunJob.perform_later(self) }
  after_update_commit :broadcast_status, if: -> { saved_change_to_status? }
  after_update_commit :notify, if: -> { saved_change_to_status? && finished? && mutating? }

  def command
    CommandCatalog.find(kind)
  end

  def mutating?
    command.mutating?
  end

  def arguments
    args = command.arguments(options)
    args += [ "-c", project.config_file ] unless project.config_file == "config/deploy.yml"
    destination.present? ? args + [ "-d", destination ] : args
  end

  # Log commands with --follow stream until stopped or FOLLOW_LIMIT passes.
  def follow?
    options["follow"] == "1" && command.fields.any? { |field| field.name == "follow" }
  end

  def display_command
    "kamal #{arguments.map { |arg| arg.match?(/\A[\w.,:\/=@-]+\z/) ? arg : arg.inspect }.join(" ")}"
  end

  def active?
    status.in?(%w[ queued running ])
  end

  def finished?
    status.in?(%w[ succeeded failed canceled ])
  end

  def duration
    (finished_at || Time.current) - started_at if started_at
  end

  def triggered_by
    trigger == "webhook" ? "Deploy webhook" : "Dashboard"
  end

  def start!(pid: nil)
    update!(status: "running", started_at: Time.current, pid: pid)
  end

  def finish!(exit_code)
    return if canceled?

    update!(status: exit_code == 0 ? "succeeded" : "failed", exit_code: exit_code, finished_at: Time.current, pid: nil)
  end

  def fail!(message)
    append_output("\n#{message}\n")
    update!(status: "failed", finished_at: Time.current, pid: nil) unless canceled?
  end

  def cancel!
    return unless active?

    pid_to_kill = pid
    update!(status: "canceled", finished_at: Time.current, pid: nil)
    Process.kill("-TERM", pid_to_kill) if pid_to_kill
  rescue Errno::ESRCH, Errno::EPERM
    # The process already exited.
  end

  def succeeded_deploy?
    status == "succeeded" && kind.in?(%w[ deploy redeploy rollback setup ])
  end

  def canceled?
    reload.status == "canceled"
  end

  # Appends a chunk to the stored output and streams it to open pages. Stored
  # output is capped so a runaway log command can't fill the database; followed
  # logs keep streaming past the cap.
  def append_output(chunk)
    chunk = clean(chunk)
    return if chunk.empty?

    if output.bytesize < OUTPUT_LIMIT
      self.class.where(id: id).update_all([ "output = output || ?", chunk ])
      self.output = output + chunk
    elsif !follow?
      return
    end

    broadcast_append_to self, target: "run_output_#{id}", html: ERB::Util.html_escape(chunk)
  end

  def self.interrupt_stale!
    active.find_each { |run| run.fail!("Interrupted: Kamal Web restarted while this command was running.") }
  end

  private
    def clean(chunk)
      chunk.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?").gsub(/\e\[[\d;?]*[A-Za-z]/, "").delete("\r")
    end

    def kind_is_known
      errors.add(:kind, "is not a supported command") unless CommandCatalog.exists?(kind)
    end

    def arguments_are_valid
      command.arguments(options) if CommandCatalog.exists?(kind)
    rescue ArgumentError => error
      errors.add(:base, error.message)
    end

    def destination_is_known
      unless project.destinations.include?(destination)
        errors.add(:destination, "is not configured in this project")
      end
    end

    def project_allows_command
      if CommandCatalog.exists?(kind) && !project.allows_command?(command)
        errors.add(:base, "#{command.label} needs the project's repository, because the config detected on the server has no env or secrets. Connect it in the project settings.")
      end
    end

    def one_operation_at_a_time
      return unless CommandCatalog.exists?(kind) && mutating?

      if (running = project.active_operation)
        errors.add(:base, "#{running.command.label} is already running for this project. Wait for it to finish or cancel it.")
      end
    end

    def broadcast_status
      broadcast_replace_to self, target: "run_status_#{id}", partial: "command_runs/status", locals: { run: self, live: true }
      broadcast_replace_to project, target: "project_activity_#{project_id}", partial: "projects/activity", locals: { project: project }
    end

    def notify
      DeployNotificationJob.perform_later(self) if project.notification_webhook_url.present?
    end
end
