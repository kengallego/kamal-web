# One request to an app's health check path through its public domain.
class HealthCheck < ApplicationRecord
  RETENTION = 24.hours

  belongs_to :project

  scope :recent, -> { where(checked_at: RETENTION.ago..) }

  def self.latest_per_url
    where(id: recent.group(:url).select("MAX(id)")).order(:url)
  end

  def up?
    error.nil? && status_code.to_i.between?(200, 399)
  end

  def certificate_days_left
    ((certificate_expires_at - Time.current) / 1.day).floor if certificate_expires_at
  end
end
