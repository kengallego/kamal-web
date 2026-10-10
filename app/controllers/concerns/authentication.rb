module Authentication
  extend ActiveSupport::Concern

  COOKIE = :kamal_ui_session

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      AccessPassword.valid_fingerprint?(cookies.signed[COOKIE])
    end

    def require_authentication
      authenticated? || request_authentication
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_session
      reset_session
      cookies.signed.permanent[COOKIE] = { value: AccessPassword.fingerprint, httponly: true, same_site: :lax }
    end

    def terminate_session
      cookies.delete(COOKIE)
      reset_session
    end
end
