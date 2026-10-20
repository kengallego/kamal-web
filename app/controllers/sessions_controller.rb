class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("flash.sessions.rate_limited") }

  def new
    redirect_to new_setup_path if User.none? && AccessPassword.problem.nil?
  end

  def create
    if (user = User.authenticate(params[:email_address], params[:password], code: params[:code]))
      start_session(user)
      audit "sessions#create"
      redirect_to after_authentication_url
    else
      Rails.logger.warn "Failed sign-in for #{params[:email_address].to_s.truncate(100).inspect} from #{request.remote_ip}"
      AuditEvent.record("sessions#failed", actor: params[:email_address].to_s.strip.truncate(100).presence || "?", user: nil)
      redirect_to new_session_path, alert: t("flash.sessions.wrong_password_or_code")
    end
    @audited = true
  end

  def destroy
    audit
    @audited = true
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
