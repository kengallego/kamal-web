# A signed-in browser. Deleting it (signing out, a password change, deleting
# the account) signs that browser out.
class Session < ApplicationRecord
  belongs_to :user
end
