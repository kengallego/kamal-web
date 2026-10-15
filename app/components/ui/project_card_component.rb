module Ui
  class ProjectCardComponent < ViewComponent::Base
    def initialize(project:, metrics: nil)
      @project, @metrics = project, metrics
    end

    def live_release(destination)
      live_releases[destination]
    end

    def live_releases
      @live_releases ||= @project.destinations.to_h { |destination| [ destination, @project.live_release(destination, @metrics || []) ] }.compact
    end

    # Deploys run outside Kamal Web count too.
    def last_deployed_at
      [ @project.last_deploy&.created_at, *live_releases.values.map(&:created_at) ].compact.max
    end

    def resource_usage(resource)
      # Keep the app and machine values paired on the busiest app host.
      metric = @metrics.reject(&:error).max_by { |sample| sample.public_send("app_#{resource}_percent") || -1 }
      [ metric&.public_send("app_#{resource}_percent"), metric&.public_send("#{resource}_percent") ]
    end
  end
end
