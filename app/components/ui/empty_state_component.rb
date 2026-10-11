module Ui
  class EmptyStateComponent < ViewComponent::Base
    def initialize(title:, description:, icon: :cube)
      @title, @description, @icon = title, description, icon
    end
  end
end
