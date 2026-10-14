module Ui
  class MeterComponent < ViewComponent::Base
    def initialize(percent:, total_percent: nil)
      @percent = percent&.clamp(0, 100)
      @total_percent = total_percent&.clamp(0, 100)
    end
  end
end
