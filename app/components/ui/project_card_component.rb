module Ui
  class ProjectCardComponent < ViewComponent::Base
    def initialize(project:, metrics: nil)
      @project, @metrics = project, metrics
    end

    def resource_usage(resource)
      # Keep the app and machine values paired on the busiest app host.
      metric = @metrics.reject(&:error).max_by { |sample| sample.public_send("app_#{resource}_percent") || -1 }
      [ metric&.public_send("app_#{resource}_percent"), metric&.public_send("#{resource}_percent") ]
    end
  end
end
