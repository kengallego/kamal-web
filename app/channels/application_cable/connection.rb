module ApplicationCable
  # Signed-in browsers get full access. A status board, which has no session,
  # may only listen to the "status_board" stream, using the cookie its page
  # sets (see StatusBoardsController).
  class Connection < ActionCable::Connection::Base
    identified_by :access, :session

    def connect
      self.session = Authentication.find_session(cookies.signed[Authentication::COOKIE]) if AccessPassword.allowed_ip?(request.remote_ip)
      self.access =
        if session
          :full
        elsif Setting.instance.status_board_viewer?(cookies.signed[StatusBoardsController::COOKIE])
          :status_board
        else
          reject_unauthorized_connection
        end
    end
  end
end
