module ApplicationHelper
  STATUS_BADGES = {
    "queued" => "badge-neutral", "running" => "badge-info", "succeeded" => "badge-success",
    "failed" => "badge-danger", "canceled" => "badge-warning"
  }.freeze

  def status_badge(status)
    render Ui::BadgeComponent.new(label: t("statuses.#{status}", default: status.to_s), tone: STATUS_BADGES.fetch(status.to_s, "badge-neutral").delete_prefix("badge-"), dot: true)
  end

  def destination_label(destination)
    destination.presence || t("common.default_destination")
  end

  def meter(percent)
    render Ui::MeterComponent.new(percent: percent)
  end

  def time_ago(time)
    t("common.ago", time: time_ago_in_words(time))
  end

  def short_sha(sha)
    sha.to_s.first(7).presence
  end

  def duration_in_words(seconds)
    return "–" unless seconds

    seconds = seconds.round
    seconds < 60 ? "#{seconds}s" : "#{seconds / 60}m #{seconds % 60}s"
  end

  # Turbo confirmation for a command that changes servers. On a protected
  # destination it asks for the destination's name to be typed instead.
  def command_confirm(project, destination, message)
    data = { turbo_confirm: message }
    data[:confirmation_word] = project.confirmation_word(destination) if project.protected_destination?(destination)
    data
  end

  # Averages a series down to at most `bars` values for a sparkline.
  def bucketed(values, bars: 96)
    return values if values.size <= bars

    values.each_slice((values.size / bars.to_f).ceil).map do |slice|
      known = slice.compact
      known.sum / known.size if known.any?
    end
  end

  def nav_link(label, path, active: current_page?(path))
    render Ui::NavLinkComponent.new(label: label, path: path, active: active)
  end

  def navigation_breadcrumbs
    return [] if current_page?(root_path)

    trail = [ [ t("common.dashboard"), root_path ] ]
    title = content_for(:title).to_s
    if @project&.persisted?
      trail << [ @project.name, project_path(@project) ]
      title = title.delete_suffix(" · #{@project.name}")
      if @run
        trail << [ t("common.activity"), project_command_runs_path(@project) ]
      elsif @session
        trail << [ t("common.console"), project_console_sessions_path(@project) ]
      elsif controller_name.in?(%w[ environment_variables project_files ])
        trail << [ t("common.settings"), project_settings_path(@project) ]
      elsif controller_path == "projects" && action_name == "edit"
        title = t("common.edit")
      end
      trail << [ title, nil ] if title.present? && title != @project.name
    else
      trail << [ title, nil ] if title.present?
    end
    trail.last[1] = nil
    trail
  end

  def form_errors(record)
    return if record.errors.none?

    tag.div(class: "mb-4 rounded-lg border border-danger/30 bg-danger/10 p-3 text-sm text-danger") do
      tag.ul(class: "list-inside list-disc") { safe_join(record.errors.full_messages.map { |message| tag.li(message) }) }
    end
  end
end
