class ServerMetric < ApplicationRecord
  include RefreshesStatusBoard
  RETENTION = 24.hours

  belongs_to :project

  scope :recent, -> { where(collected_at: RETENTION.ago..) }
  scope :successful, -> { where(error: nil) }

  def memory_percent
    percent(memory_used, memory_total)
  end

  def disk_percent
    percent(disk_used, disk_total)
  end

  def load_percent
    percent(load_1, cpu_count) if load_1
  end

  private
    def percent(used, total)
      (used.to_f / total * 100).round(1) if used && total.to_f.positive?
    end
end
