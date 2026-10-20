# Accounts. Every account has full access, so anyone signed in can add or
# remove others; the Activity page shows who did.
class UsersController < ApplicationController
  def index
    @users = User.ordered
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: [ :name, :email_address, :password, :password_confirmation ]))

    if @user.save
      redirect_to users_path, notice: t("flash.saved", name: @user.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @user = User.find(params[:id])

    if @user == current_user
      redirect_to users_path, alert: t("flash.users.not_yourself")
    else
      @user.destroy!
      redirect_to users_path, notice: t("flash.deleted", name: @user.name), status: :see_other
    end
  end
end
