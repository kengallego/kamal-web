class SettingsController < ApplicationController
  before_action :require_admin

  def edit
    @setting = Setting.instance
  end

  def update
    @setting = Setting.instance
    @setting.update!(params.expect(setting: [ :status_board_enabled ]))
    redirect_to edit_settings_path, notice: "Settings saved."
  end

  def regenerate_status_board_token
    Setting.instance.regenerate_status_board_token!
    redirect_to edit_settings_path, notice: "Status board URL regenerated."
  end
end
