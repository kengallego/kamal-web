# Applies the browser's theme and language. The language comes from the
# locale cookie, then the Accept-Language header, then English.
module Preferences
  extend ActiveSupport::Concern

  THEMES = %w[ system light dark ].freeze

  included do
    around_action :switch_locale
    helper_method :current_theme
  end

  private
    def current_theme
      THEMES.include?(cookies[:theme]) ? cookies[:theme] : "system"
    end

    def switch_locale(&action)
      I18n.with_locale(requested_locale || I18n.default_locale, &action)
    end

    def requested_locale
      available = I18n.available_locales.map(&:to_s)
      return cookies[:locale] if available.include?(cookies[:locale])

      request.headers["Accept-Language"].to_s.split(",").lazy.map { |entry| locale_for(entry.split(";").first.to_s.strip) }.find(&:itself)
    end

    # An exact match first ("pt-BR"), then the language alone, so "pt-PT" or
    # "zh-TW" still get Portuguese or Chinese.
    def locale_for(code)
      available = I18n.available_locales.map(&:to_s)
      language = code.split("-").first.to_s.downcase
      available.find { |locale| locale.casecmp?(code) } || available.find { |locale| locale.split("-").first == language }
    end
end
