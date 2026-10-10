class DiscoverKamalAppsJob < ApplicationJob
  queue_as :default

  def perform
    KamalDiscovery.new.call
  end
end
