module Ui
  class ShellComponent < ViewComponent::Base
    def initialize(projects:, setting:)
      @projects, @setting = projects, setting
    end
  end
end
