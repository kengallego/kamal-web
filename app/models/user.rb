class User < ApplicationRecord
  ROLES = %w[ viewer deployer admin ].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :command_runs, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 10 }, allow_nil: true
  validate :keeps_an_admin, on: :update

  before_destroy :ensure_not_last_admin

  scope :admins, -> { where(role: "admin") }

  def display_name
    name.presence || email_address
  end

  def admin?
    role == "admin"
  end

  def deployer?
    role.in?(%w[ deployer admin ])
  end

  # Whether this user may run commands that need the given role.
  def can?(required_role)
    ROLES.index(role) >= ROLES.index(required_role.to_s)
  end

  private
    def keeps_an_admin
      if role_changed?(from: "admin") && User.admins.where.not(id: id).none?
        errors.add(:role, "can't be changed because this is the last admin")
      end
    end

    def ensure_not_last_admin
      if admin? && User.admins.where.not(id: id).none?
        errors.add(:base, "The last admin can't be deleted")
        throw :abort
      end
    end
end
