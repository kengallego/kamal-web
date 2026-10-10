class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if AccessPassword.matches?(params[:password], code: params[:code])
      start_session
      redirect_to after_authentication_url
    else
      Rails.logger.warn "Failed sign-in from #{request.remote_ip}"
      redirect_to new_session_path, alert: AccessPassword.two_factor? ? "Wrong password or code." : "Wrong password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
