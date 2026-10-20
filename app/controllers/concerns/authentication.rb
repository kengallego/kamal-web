module Authentication
  extend ActiveSupport::Concern

  COOKIE = :kamal_web_session

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  # The signed-in session for a signed cookie value, used by Action Cable too.
  def self.find_session(value)
    Session.find_by(id: value) if value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)
  end

  private
    def authenticated?
      resume_session.present?
    end

    def current_user
      Current.user
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= Authentication.find_session(cookies.signed[COOKIE])
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_session(user)
      reset_session
      user.update_columns(last_signed_in_at: Time.current)
      Current.session = user.sessions.create!(ip_address: request.remote_ip, user_agent: request.user_agent.to_s.truncate(255))
      cookies.signed.permanent[COOKIE] = { value: Current.session.id, httponly: true, same_site: :lax }
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(COOKIE)
      reset_session
    end
end
