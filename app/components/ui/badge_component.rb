module Ui
  class BadgeComponent < ViewComponent::Base
    TONES = %w[ neutral success danger warning info ].freeze

    def initialize(label:, tone: :neutral, dot: false)
      @label, @tone, @dot = label, TONES.include?(tone.to_s) ? tone : :neutral, dot
    end
  end
end
