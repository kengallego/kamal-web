class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @setting.ensure_ssh_key!
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

  def reset_ignored_services
    Setting.instance.update!(ignored_services: [])
    redirect_to edit_settings_path, notice: "Removed apps will be detected again on the next scan."
  end
end
