class DiscoveriesController < ApplicationController
  def create
    result = KamalDiscovery.new.call

    if result.error
      redirect_to root_path, alert: result.error
    elsif result.apps.empty?
      redirect_to root_path, notice: t("flash.discoveries.none")
    else
      added = result.created.map(&:name)
      redirect_to root_path, notice: added.any? ? t("flash.discoveries.added", count: result.apps.size, names: added.to_sentence) : t("flash.discoveries.all_added", count: result.apps.size)
    end
  end
end
