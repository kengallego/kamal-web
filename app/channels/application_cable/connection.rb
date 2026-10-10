module ApplicationCable
  class Connection < ActionCable::Connection::Base
    def connect
      reject_unauthorized_connection unless AccessPassword.valid_fingerprint?(cookies.signed[Authentication::COOKIE])
    end
  end
end
