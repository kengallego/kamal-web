module Ui
  class IconComponent < ViewComponent::Base
    PATHS = {
      sun: "M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M4.93 4.93l1.42 1.42 M17.65 17.65l1.42 1.42 M4.93 19.07l1.42-1.42 M17.65 6.35l1.42-1.42",
      moon: "M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z",
      monitor: "M3 3h18v13H3z M12 16v5 M8 21h8",
      grid: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
      cube: "m12 3 9 5-9 5-9-5 9-5Z M3 8v9l9 5 9-5V8 M12 13v9 M7.5 5.5l9 5",
      server: "M4 3h16v7H4z M4 14h16v7H4z M7 6.5h.01 M7 17.5h.01 M11 6.5h6 M11 17.5h6",
      activity: "M3 12h4l3-8 4 16 3-8h4",
      plus: "M12 5v14 M5 12h14",
      arrow: "M5 12h14 M13 6l6 6-6 6",
      chevron: "m9 5 7 7-7 7",
      refresh: "M20 7v5h-5 M4 17v-5h5 M6.1 6a8 8 0 0 1 13.1 2 M17.9 18A8 8 0 0 1 4.8 16",
      settings: "M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3Z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
      logout: "M9 4H4v16h5 M10 12h11 M16 7l5 5-5 5",
      terminal: "m5 6 6 6-6 6 M13 18h6",
      logs: "M4 5h16 M4 10h16 M4 15h10 M4 20h7",
      shield: "m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z m-4 9 3 3 5-5",
      branch: "M6 3v12 M6 15a3 3 0 1 0 0 6 3 3 0 0 0 0-6 M6 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4 M18 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4 M18 7v2a6 6 0 0 1-6 6H9",
      globe: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M3 12h18 M12 3a18 18 0 0 1 0 18 18 18 0 0 1 0-18",
      code: "m8 7-5 5 5 5 M16 7l5 5-5 5 M14 4l-4 16",
      menu: "M4 6h16 M4 12h16 M4 18h16",
      check: "m5 12 4 4L19 6",
      info: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 11v6 M12 7h.01"
    }.freeze

    def initialize(name:, size: 18, **attributes)
      @name, @size, @attributes = name.to_sym, size, attributes
    end

    def call
      tag.svg(viewBox: "0 0 24 24", width: @size, height: @size, fill: "none", stroke: "currentColor",
        "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true,
        class: "shrink-0", **@attributes) { tag.path(d: PATHS.fetch(@name)) }
    end
  end
end
