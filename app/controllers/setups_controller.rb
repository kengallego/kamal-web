# Creates the first account. Only reachable while there are none, and only
# with KAMAL_WEB_PASSWORD (and KAMAL_WEB_TOTP_SECRET's code, when set), which
# stops working once the account exists.
class SetupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_setup_path, alert: t("flash.sessions.rate_limited") }
  before_action :require_no_accounts

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: [ :name, :email_address, :password, :password_confirmation ]))

    if !AccessPassword.matches?(params[:instance_password], code: params[:code])
      Rails.logger.warn "Failed setup from #{request.remote_ip}"
      flash.now[:alert] = AccessPassword.two_factor? ? t("flash.sessions.wrong_password_or_code") : t("flash.sessions.wrong_password")
      render :new, status: :unprocessable_entity
    elsif User.transaction { User.none? && @user.save }
      start_session(@user)
      audit "setups#create", subject: @user
      @audited = true
      redirect_to root_url, notice: t("flash.setups.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def require_no_accounts
      redirect_to new_session_path if User.exists?
    end
end
