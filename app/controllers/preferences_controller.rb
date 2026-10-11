# Theme and language, remembered per browser. Also offered on the sign-in page.
class PreferencesController < ApplicationController
  allow_unauthenticated_access

  def update
    cookies.permanent[:theme] = params[:theme] if Preferences::THEMES.include?(params[:theme])
    cookies.permanent[:locale] = params[:locale] if I18n.available_locales.map(&:to_s).include?(params[:locale])
    redirect_back fallback_location: root_path
  end
end
