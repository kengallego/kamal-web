# Turns an authenticator app on or off for the signed-in account. The new
# secret waits in the session until a code from the app confirms it.
class TwoFactorsController < ApplicationController
  def new
    session[:pending_otp_secret] ||= Totp.generate_secret
    @secret = session[:pending_otp_secret]
  end

  def create
    secret = session[:pending_otp_secret]

    if secret && Totp.verify(secret, params[:code])
      current_user.update!(otp_secret: secret)
      session.delete(:pending_otp_secret)
      redirect_to edit_account_path, notice: t("flash.two_factors.enabled")
    else
      @audited = true
      redirect_to new_two_factor_path, alert: t("flash.two_factors.wrong_code")
    end
  end

  def destroy
    if current_user.authenticate(params[:current_password].to_s)
      current_user.update!(otp_secret: nil)
      redirect_to edit_account_path, notice: t("flash.two_factors.disabled"), status: :see_other
    else
      @audited = true
      redirect_to edit_account_path, alert: t("flash.accounts.wrong_password"), status: :see_other
    end
  end
end
