module Ui
  class MeterComponent < ViewComponent::Base
    def initialize(percent:)
      @percent = percent.to_f.clamp(0, 100)
      @color = @percent >= 90 ? "bg-danger" : @percent >= 70 ? "bg-warning" : "bg-success"
    end
  end
end
