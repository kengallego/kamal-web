class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @setting.ensure_ssh_key!
  end

  def update
    @setting = Setting.instance

    if @setting.update(params.expect(setting: [ :status_board_enabled, :alert_disk_percent, :alert_memory_percent, :scheduled_backups_enabled, :scheduled_backups_keep ]))
      redirect_to edit_settings_path, notice: t("flash.settings.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate_status_board_token
    Setting.instance.regenerate_status_board_token!
    redirect_to edit_settings_path, notice: t("flash.settings.status_board_regenerated")
  end

  def reset_ignored_services
    Setting.instance.update!(ignored_services: [])
    redirect_to edit_settings_path, notice: t("flash.settings.detect_again")
  end
end
