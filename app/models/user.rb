# Someone who can sign in. Every account has full access: whoever signs in
# controls the servers Kamal Web reaches. Accounts exist so that what happens
# is recorded under a name (see AuditEvent) and access can be revoked per person.
#
# The first account is created with KAMAL_WEB_PASSWORD (see SetupsController),
# which can't sign in once any account exists.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  encrypts :otp_secret

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: AccessPassword::MINIMUM_LENGTH }, allow_nil: true

  scope :ordered, -> { order(Arel.sql("LOWER(name)")) }

  # A password change signs out every other browser.
  after_update :end_other_sessions, if: :saved_change_to_password_digest?

  def self.authenticate(email_address, password, code: nil)
    user = authenticate_by(email_address: email_address.to_s, password: password.to_s)
    user if user&.valid_code?(code)
  end

  def label
    "#{name} <#{email_address}>"
  end

  def two_factor?
    otp_secret.present?
  end

  # Accounts without their own authenticator use KAMAL_WEB_TOTP_SECRET, when set.
  def valid_code?(code)
    secret = otp_secret.presence || AccessPassword.totp_secret
    secret.nil? || Totp.verify(secret, code)
  end

  private
    def end_other_sessions
      sessions.where.not(id: Current.session&.id).destroy_all
    end
end
