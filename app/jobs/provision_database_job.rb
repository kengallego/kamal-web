class ProvisionDatabaseJob < ApplicationJob
  queue_as :commands

  discard_on ActiveJob::DeserializationError

  def perform(database)
    database.provision!
  end
end
