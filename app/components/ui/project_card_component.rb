module Ui
  class ProjectCardComponent < ViewComponent::Base
    def initialize(project:, metrics: nil)
      @project, @metrics = project, metrics
    end
  end
end
