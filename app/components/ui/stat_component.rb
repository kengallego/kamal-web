module Ui
  class StatComponent < ViewComponent::Base
    def initialize(label:, value:, icon:, caption: nil)
      @label, @value, @icon, @caption = label, value, icon, caption
    end
  end
end
