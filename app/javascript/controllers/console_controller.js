import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

// Attaches an xterm.js terminal to a ConsoleChannel subscription.
export default class extends Controller {
  static targets = [ "screen", "status" ]
  static values = { sessionId: Number, messages: Object }

  async connect() {
    this.terminal = new Terminal({
      cursorBlink: true,
      fontFamily: '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace',
      fontSize: 13,
      scrollback: 5000,
      theme: { background: "#111722", foreground: "#e2e8f0", cursor: "#b49af4" }
    })
    this.fitAddon = new FitAddon()
    this.terminal.loadAddon(this.fitAddon)
    this.terminal.open(this.screenTarget)
    this.fitAddon.fit()
    this.terminal.focus()

    this.resizeObserver = new ResizeObserver(() => this.fitAddon.fit())
    this.resizeObserver.observe(this.screenTarget)

    this.subscription = await cable.subscribeTo(
      { channel: "ConsoleChannel", id: this.sessionIdValue, rows: this.terminal.rows, cols: this.terminal.cols },
      {
        connected: () => this.setStatus(this.message("connected"), "success"),
        disconnected: () => this.ended || this.setStatus(this.message("disconnected"), "danger"),
        rejected: () => this.setStatus(this.message("rejected"), "danger"),
        received: (message) => this.received(message)
      }
    )

    this.terminal.onData((data) => this.ended || this.subscription.send({ type: "input", data }))
    this.terminal.onResize(({ rows, cols }) => this.subscription.send({ type: "resize", rows, cols }))
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.subscription?.unsubscribe()
    this.terminal?.dispose()
  }

  received(message) {
    if (message.type === "output") {
      this.terminal.write(Uint8Array.from(atob(message.data), (char) => char.charCodeAt(0)))
    } else if (message.type === "exit") {
      this.ended = true
      const code = message.code ?? "unknown"
      this.setStatus(this.message("ended").replace("%{code}", code), code === 0 ? "neutral" : "danger")
      this.terminal.write(`\r\n\x1b[2m[${this.message("ended_short")}]\x1b[0m\r\n`)
    }
  }

  // Texts come translated from the page, in data-console-messages-value.
  message(key) {
    return this.messagesValue[key] ?? key
  }

  setStatus(text, tone) {
    this.statusTarget.textContent = text
    this.statusTarget.className = `badge badge-${tone}`
  }
}
