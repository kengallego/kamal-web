module Ui
  class PanelComponent < ViewComponent::Base
    def initialize(title: nil, **attributes)
      @title, @attributes = title, attributes
      @attributes[:class] = [ "card", @attributes[:class] ]
    end
  end
end
