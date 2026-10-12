import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, copied: { type: String, default: "Copied" }, error: { type: String, default: "Could not copy" } }

  disconnect() {
    this.restore()
  }

  async copy(event) {
    event.preventDefault()
    if (this.copying) return
    this.copying = true
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.feedback(this.copiedValue)
    } catch {
      this.feedback(this.errorValue)
    } finally {
      this.copying = false
    }
  }

  feedback(message) {
    this.restore()
    this.originalNodes = Array.from(this.element.childNodes)
    this.element.textContent = message
    this.element.setAttribute("aria-live", "polite")
    this.timer = setTimeout(() => this.restore(), 1600)
  }

  restore() {
    clearTimeout(this.timer)
    if (this.originalNodes) {
      this.element.replaceChildren(...this.originalNodes)
      this.originalNodes = null
      this.element.removeAttribute("aria-live")
    }
  }
}
