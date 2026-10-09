class Setting < ApplicationRecord
  has_secure_token :status_board_token, length: 32

  def self.instance
    first || create!
  end

  def regenerate_status_board_token!
    regenerate_status_board_token
  end
end
