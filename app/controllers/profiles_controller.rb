class ProfilesController < ApplicationController
  def edit
  end

  def update
    attributes = params.expect(user: [ :name, :email_address, :password, :password_confirmation, :password_challenge ])

    if attributes[:password].blank?
      attributes = attributes.except(:password, :password_confirmation, :password_challenge)
    end

    if current_user.update(attributes)
      current_user.sessions.where.not(id: Current.session.id).destroy_all if attributes[:password].present?
      redirect_to edit_profile_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
