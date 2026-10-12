import { Controller } from "@hotwired/stimulus"

// Protected submissions are rebuilt after the word is supplied so Turbo sends
// the confirmation parameter to the server along with the original form.
export default class extends Controller {
  static targets = ["message", "word", "input", "confirm", "challenge"]

  connect() {
    this.previousConfirm = window.Turbo.config.forms.confirm
    this.confirm = (message, form, submitter) => this.ask(message, form, submitter)
    window.Turbo.config.forms.confirm = this.confirm
  }

  disconnect() {
    if (window.Turbo.config.forms.confirm === this.confirm) {
      window.Turbo.config.forms.confirm = this.previousConfirm
    }
    this.pendingConfirmation?.(false)
  }

  ask(message, form, submitter) {
    const word = submitter?.dataset.confirmationWord || form.dataset.confirmationWord
    if (form.dataset.confirmed) {
      delete form.dataset.confirmed
      return Promise.resolve(true)
    }
    if (this.element.open) return Promise.resolve(false)

    this.expected = word || ""
    this.messageTarget.textContent = message
    this.wordTarget.textContent = this.expected
    this.challengeTarget.hidden = !word
    this.inputTarget.value = ""
    this.check()
    this.element.returnValue = ""
    this.element.showModal()
    if (word) this.inputTarget.focus()
    else this.element.querySelector('[value="cancel"]').focus()

    if (!word) {
      return new Promise(resolve => {
        this.pendingConfirmation = resolve
        this.element.addEventListener("close", () => {
          this.pendingConfirmation = null
          resolve(this.element.returnValue === "confirm")
        }, { once: true })
      })
    }

    this.element.addEventListener("close", () => {
      if (this.element.returnValue !== "confirm") return
      form.querySelector("input[name=confirmation]")?.remove()
      const input = Object.assign(document.createElement("input"), { type: "hidden", name: "confirmation", value: word })
      form.append(input)
      form.dataset.confirmed = "true"
      form.requestSubmit(submitter?.form === form ? submitter : null)
    }, { once: true })
    return Promise.resolve(false)
  }

  check() {
    this.confirmTarget.disabled = !!this.expected && this.inputTarget.value.trim() !== this.expected
  }
}
