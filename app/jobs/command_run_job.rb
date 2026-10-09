class CommandRunJob < ApplicationJob
  queue_as :commands

  discard_on ActiveJob::DeserializationError

  def perform(run)
    KamalRunner.new(run).call
  end
end
