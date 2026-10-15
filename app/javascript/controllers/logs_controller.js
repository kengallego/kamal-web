import { Controller } from "@hotwired/stimulus"

// Runs the logs as soon as the tab opens, and stops a followed run when it is
// replaced, stopped or the page is left, instead of streaming for 30 minutes.
export default class extends Controller {
  static targets = [ "form", "replace", "run" ]

  connect() {
    if (!document.documentElement.hasAttribute("data-turbo-preview")) this.formTarget.requestSubmit()
  }

  disconnect() {
    this.cancel({ keepalive: true })
  }

  prepare() {
    this.replaceTarget.value = this.hasRunTarget ? this.runTarget.dataset.runId : ""
  }

  stop(event) {
    event.currentTarget.disabled = true
    this.cancel()
  }

  cancel(options = {}) {
    if (!this.hasRunTarget || this.runTarget.dataset.follow !== "true") return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.runTarget.dataset.cancelUrl, { method: "POST", headers: { "X-CSRF-Token": token }, ...options })
    this.runTarget.dataset.follow = "false"
  }
}
