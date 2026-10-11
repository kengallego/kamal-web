class EnvironmentVariable < ApplicationRecord
  belongs_to :project

  encrypts :value

  normalizes :destination, with: ->(d) { d.presence }

  validates :key, presence: true, format: { with: /\A[A-Za-z_][A-Za-z0-9_]*\z/, message: :invalid_name },
    uniqueness: { scope: [ :project_id, :destination ] }
end
