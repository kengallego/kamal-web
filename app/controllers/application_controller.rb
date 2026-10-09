class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

  private
    def current_user
      Current.user
    end

    def require_admin
      require_role "admin"
    end

    def require_role(role)
      unless current_user&.can?(role)
        redirect_back fallback_location: root_path, alert: "You need the #{role} role to do that."
      end
    end
end
