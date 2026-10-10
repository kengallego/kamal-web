# Requests per minute by status class, for the bar chart on the Proxy tab.
class TrafficChart
  CLASSES = %w[ 2xx 3xx 4xx 5xx ].freeze
  Bucket = Data.define(:time, :counts) do
    def total
      counts.values.sum
    end
  end

  attr_reader :minutes

  def initialize(requests, minutes: 60, now: Time.current)
    @minutes = minutes
    @start = now.beginning_of_minute - (minutes - 1).minutes
    @requests = requests
  end

  def buckets
    @buckets ||= begin
      grouped = @requests.select(&:time).group_by { |request| request.time.beginning_of_minute }
      Array.new(minutes) do |index|
        time = @start + index.minutes
        counts = CLASSES.index_with { |status_class| 0 }
        grouped.fetch(time, []).each { |request| counts[request.status_class] += 1 if counts.key?(request.status_class) }
        Bucket.new(time: time, counts: counts)
      end
    end
  end

  def peak
    buckets.map(&:total).max.to_i
  end

  def empty?
    peak.zero?
  end
end
