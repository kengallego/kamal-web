module Ui
  class NavigationComponent < ViewComponent::Base
    def initialize(projects:, setting:)
      @projects, @setting = projects, setting
    end
  end
end
