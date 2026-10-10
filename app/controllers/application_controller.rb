class ApplicationController < ActionController::Base
  include Authentication
  before_action :require_allowed_ip
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    # The deploy webhook and the status board use their own secret URLs and
    # skip this, so CI and wallboards keep working from anywhere.
    def require_allowed_ip
      render plain: "Kamal Web isn't reachable from #{request.remote_ip}.\n", status: :forbidden unless AccessPassword.allowed_ip?(request.remote_ip)
    end
end
