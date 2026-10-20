# The signed-in account for the current request or console connection, so
# models can record who did something without it being passed around.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :ip_address
  delegate :user, to: :session, allow_nil: true
end
