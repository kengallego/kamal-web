module Ui
  class PageHeaderComponent < ViewComponent::Base
    def initialize(title:, description: nil, eyebrow: nil)
      @title, @description, @eyebrow = title, description, eyebrow
    end
  end
end
