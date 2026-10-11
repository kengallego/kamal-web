module Ui
  class ThemeSwitcherComponent < ViewComponent::Base
    ICONS = { "system" => :monitor, "light" => :sun, "dark" => :moon }.freeze

    def initialize(align: :end)
      @alignment = align == :start ? "left-0" : "right-0"
    end
  end
end
