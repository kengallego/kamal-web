class DiscoveriesController < ApplicationController
  def create
    result = KamalDiscovery.new.call

    if result.error
      redirect_to root_path, alert: result.error
    elsif result.apps.empty?
      redirect_to root_path, notice: "No Kamal apps are running on this server."
    else
      added = result.created.map(&:name)
      redirect_to root_path, notice: "Found #{helpers.pluralize(result.apps.size, "Kamal app")} on this server#{added.any? ? ", added #{added.to_sentence}" : ", all already added"}."
    end
  end
end
