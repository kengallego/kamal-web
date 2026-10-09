import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["git", "local"]

  connect() { this.toggle() }

  toggle() {
    const selected = this.element.querySelector("input[name$='[source_kind]']:checked")?.value || "git"
    this.gitTarget.hidden = selected !== "git"
    this.localTarget.hidden = selected !== "local"
  }
}
