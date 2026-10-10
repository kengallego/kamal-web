# Tells open status boards to reload when a record they show changes.
module RefreshesStatusBoard
  extend ActiveSupport::Concern

  included do
    after_commit :refresh_status_board
  end

  private
    def refresh_status_board
      Turbo::StreamsChannel.broadcast_refresh_later_to(StatusBoardsController::STREAM) if Setting.instance.status_board_enabled?
    end
end
