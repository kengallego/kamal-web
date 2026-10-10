class BackupsController < ApplicationController
  def show
    send_data InstanceBackup.write(StringIO.new).string, filename: InstanceBackup.filename, type: "application/gzip"
  end

  def create
    file = params.require(:backup)
    manifest = InstanceBackup.stage!(file.path)
    restart_soon
    redirect_to edit_settings_path, notice: "Backup from #{manifest["created_at"]&.then { |time| l(Time.zone.parse(time), format: :long) }} accepted. " \
      "Kamal Web is restarting to restore it; sign in again in a few seconds."
  rescue InstanceBackup::Invalid, ActionController::ParameterMissing => error
    redirect_to edit_settings_path, alert: error.is_a?(InstanceBackup::Invalid) ? error.message : "Choose a backup file."
  end

  private
    # The backup is applied at boot. Stopping the container's main process
    # makes Docker restart it, because Kamal runs apps with --restart
    # unless-stopped. Outside production the server is restarted by hand.
    def restart_soon
      return unless Rails.env.production?

      Thread.new do
        sleep 2
        Process.kill("TERM", 1)
      end
    end
end
