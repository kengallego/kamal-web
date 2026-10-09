class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: %i[ edit update destroy ]

  def index
    @users = User.order(:email_address)
  end

  def new
    @user = User.new(role: "deployer")
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to users_path, notice: "#{@user.email_address} can now sign in."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = user_params
    attributes.delete(:password) if attributes[:password].blank?

    if @user.update(attributes)
      @user.sessions.where.not(id: Current.session.id).destroy_all if attributes[:password].present?
      redirect_to users_path, notice: "#{@user.email_address} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You can't delete your own account."
    elsif @user.destroy
      redirect_to users_path, notice: "#{@user.email_address} deleted.", status: :see_other
    else
      redirect_to users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: [ :name, :email_address, :role, :password ])
    end
end
