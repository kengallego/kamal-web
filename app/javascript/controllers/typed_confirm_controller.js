import { Controller } from "@hotwired/stimulus"

// Turbo's confirmations. Forms with data-confirmation-word (commands that
// change a protected destination) ask for that word to be typed, then submit
// again with it as the confirmation param; the rest use the browser's confirm.
export default class extends Controller {
  static targets = [ "message", "word", "input", "confirm" ]

  connect() {
    window.Turbo.config.forms.confirm = (message, form, submitter) => this.ask(message, form, submitter)
  }

  disconnect() {
    window.Turbo.config.forms.confirm = undefined
  }

  ask(message, form, submitter) {
    const word = submitter?.dataset.confirmationWord || form.dataset.confirmationWord
    if (!word) return Promise.resolve(window.confirm(message))

    // The resubmission below already carries the typed word.
    if (form.dataset.confirmed) {
      delete form.dataset.confirmed
      return Promise.resolve(true)
    }

    this.expected = word
    this.messageTarget.textContent = message
    this.wordTarget.textContent = word
    this.inputTarget.value = ""
    this.check()
    this.element.returnValue = ""
    this.element.showModal()
    this.inputTarget.focus()

    this.element.addEventListener("close", () => {
      if (this.element.returnValue !== "confirm") return

      form.querySelector("input[name=confirmation]")?.remove()
      const input = Object.assign(document.createElement("input"), { type: "hidden", name: "confirmation", value: word })
      form.append(input)
      form.dataset.confirmed = "true"
      form.requestSubmit(submitter?.form === form ? submitter : null)
    }, { once: true })

    // Turbo's submission was built before the word was typed.
    return Promise.resolve(false)
  }

  check() {
    this.confirmTarget.disabled = this.inputTarget.value.trim() !== this.expected
  }
}
