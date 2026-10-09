import { Controller } from "@hotwired/stimulus"

// Attached to run status badges that arrive by broadcast. Shows a browser
// notification when a command finishes while the tab is in the background.
export default class extends Controller {
  static values = { status: String, label: String }

  connect() {
    if (!("Notification" in window)) return
    if (Notification.permission === "default") Notification.requestPermission()

    const finished = ["succeeded", "failed", "canceled"].includes(this.statusValue)
    if (finished && document.visibilityState !== "visible" && Notification.permission === "granted") {
      new Notification(`${this.labelValue} ${this.statusValue}`)
    }
  }
}
