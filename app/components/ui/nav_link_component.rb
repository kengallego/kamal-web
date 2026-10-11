module Ui
  class NavLinkComponent < ViewComponent::Base
    def initialize(label:, path:, active: false, icon: nil)
      @label, @path, @active, @icon = label, path, active, icon
    end
  end
end
