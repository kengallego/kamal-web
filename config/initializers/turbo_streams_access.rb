# Status board connections may only subscribe to the status board stream.
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.prepend(Module.new do
    def subscribed
      return reject unless connection.access == :full || verified_stream_name_from_params == StatusBoardsController::STREAM

      super
    end
  end)
end
