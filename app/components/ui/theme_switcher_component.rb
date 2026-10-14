module Ui
  class ThemeSwitcherComponent < ViewComponent::Base
    ICONS = { "system" => :monitor, "light" => :sun, "dark" => :moon }.freeze

    def initialize(align: :end, placement: :bottom)
      @alignment = { start: "left-0", center: "left-1/2 -translate-x-1/2" }.fetch(align, "right-0")
      @position = placement == :top ? "bottom-full mb-2" : "top-full mt-2"
    end
  end
end
