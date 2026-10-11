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

  def nav_link(label, path, active: current_page?(path))
    render Ui::NavLinkComponent.new(label: label, path: path, active: active)
  end

  def form_errors(record)
    return if record.errors.none?

    tag.div(class: "mb-4 rounded-lg border border-danger/30 bg-danger/10 p-3 text-sm text-danger") do
      tag.ul(class: "list-inside list-disc") { safe_join(record.errors.full_messages.map { |message| tag.li(message) }) }
    end
  end
end
