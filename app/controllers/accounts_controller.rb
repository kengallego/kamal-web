# The signed-in person's own name, email, password and authenticator app.
class AccountsController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if !@user.authenticate(params[:current_password].to_s)
      @user.assign_attributes(account_params)
      @user.errors.add(:base, t("flash.accounts.wrong_password"))
      render :edit, status: :unprocessable_entity
    elsif @user.update(account_params)
      redirect_to edit_account_path, notice: t("flash.accounts.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(user: [ :name, :email_address, :password, :password_confirmation ]).tap do |permitted|
        permitted.extract!(:password, :password_confirmation) if permitted[:password].blank?
      end
    end
end
