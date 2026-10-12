import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  close() {
    this.menuTargets.forEach(menu => {
      if (menu.open) {
        menu.open = false
        menu.querySelector("summary")?.focus()
      }
    })
  }

  dismiss(event) {
    this.menuTargets.forEach(menu => {
      if (menu.open && !menu.contains(event.target)) menu.open = false
    })
  }
}
