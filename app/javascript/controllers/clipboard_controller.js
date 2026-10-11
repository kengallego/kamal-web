import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, copied: { type: String, default: "Copied" } }

  copy(event) {
    event.preventDefault()
    navigator.clipboard.writeText(this.textValue)
    const original = this.element.textContent
    this.element.textContent = this.copiedValue
    setTimeout(() => { this.element.textContent = original }, 1200)
  }
}
