module ApplicationHelper
  STATUS_BADGES = {
    "queued" => "badge-neutral", "running" => "badge-info", "succeeded" => "badge-success",
    "failed" => "badge-danger", "canceled" => "badge-warning"
  }.freeze

  def status_badge(status)
    tag.span status, class: "badge #{STATUS_BADGES.fetch(status.to_s, "badge-neutral")}"
  end

  def destination_label(destination)
    destination.presence || "default"
  end

  def meter(percent)
    percent = percent.to_f.clamp(0, 100)
    color = percent >= 90 ? "bg-red-400" : percent >= 70 ? "bg-amber-400" : "bg-emerald-400"
    tag.div(class: "meter") { tag.span(class: color, style: "width: #{percent}%") }
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
    link_to label, path, class: [ "flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm",
      active ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:bg-zinc-900 hover:text-zinc-100" ]
  end

  def form_errors(record)
    return if record.errors.none?

    tag.div(class: "mb-4 rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-300") do
      tag.ul(class: "list-inside list-disc") { safe_join(record.errors.full_messages.map { |message| tag.li(message) }) }
    end
  end
end
