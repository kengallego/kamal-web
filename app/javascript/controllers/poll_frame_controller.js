import { Controller } from "@hotwired/stimulus"

// Reloads a turbo frame every few seconds until a response contains an element
// with data-poll-final.
export default class extends Controller {
  static values = { interval: { type: Number, default: 4000 } }

  connect() {
    this.element.addEventListener("turbo:frame-load", this.scheduled)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("turbo:frame-load", this.scheduled)
  }

  scheduled = () => {
    clearTimeout(this.timer)
    if (this.element.querySelector("[data-poll-final]")) return
    this.timer = setTimeout(() => this.element.reload(), this.intervalValue)
  }
}
