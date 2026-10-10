# Bridges an xterm.js terminal in the browser to a ConsoleProcess. Output is
# sent base64-encoded because PTY chunks can split multi-byte characters.
class ConsoleChannel < ApplicationCable::Channel
  def subscribed
    @session = ConsoleSession.find_by(id: params[:id])
    return reject unless @session&.claim!

    @process = ConsoleProcess.new(@session,
      on_output: ->(data) { transmit({ type: "output", data: Base64.strict_encode64(data) }) },
      on_exit: ->(code) { exited(code) })
    @process.resize(params[:rows].to_i, params[:cols].to_i)
    @process.start
  end

  def receive(data)
    case data["type"]
    when "input" then @process&.write(data["data"].to_s)
    when "resize" then @process&.resize(data["rows"].to_i, data["cols"].to_i)
    end
  end

  def unsubscribed
    @process&.stop
    @session&.finish!
  end

  private
    def exited(code)
      @session.finish!(code)
      transmit({ type: "exit", code: code })
    rescue StandardError
      # The browser already went away.
    end
end
