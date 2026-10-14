class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @setting.ensure_ssh_key!
    @self_update_problem = SelfUpdate.new.problem
  end

  def update
    @setting = Setting.instance

    if @setting.update(params.expect(setting: [ :status_board_enabled, :alert_disk_percent, :alert_memory_percent, :scheduled_backups_enabled, :scheduled_backups_keep, :auto_update_enabled ]))
      redirect_to edit_settings_path, notice: t("flash.settings.saved")
    else
      @self_update_problem = SelfUpdate.new.problem
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate_status_board_token
    Setting.instance.regenerate_status_board_token!
    redirect_to edit_settings_path, notice: t("flash.settings.status_board_regenerated")
  end

  def update_instance
    setting = Setting.instance

    if setting.update_available? && !setting.auto_update_running? && SelfUpdate.new.launch("v#{setting.latest_version}")
      redirect_to edit_settings_path(anchor: "version"), notice: t("flash.settings.updating", version: setting.latest_version)
    else
      redirect_to edit_settings_path(anchor: "version"), alert: t("flash.settings.update_not_started")
    end
  end

  def reset_ignored_services
    Setting.instance.update!(ignored_services: [])
    redirect_to edit_settings_path, notice: t("flash.settings.detect_again")
  end
end
