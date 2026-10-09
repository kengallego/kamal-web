import { Controller } from "@hotwired/stimulus"

// Keeps a log pane pinned to the bottom while new output streams in, unless the
// user scrolled up to read.
export default class extends Controller {
  connect() {
    this.pinned = true
    this.scrollToBottom()
    this.observer = new MutationObserver(() => { if (this.pinned) this.scrollToBottom() })
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
    this.element.addEventListener("scroll", this.onScroll)
  }

  disconnect() {
    this.observer.disconnect()
    this.element.removeEventListener("scroll", this.onScroll)
  }

  onScroll = () => {
    const { scrollTop, scrollHeight, clientHeight } = this.element
    this.pinned = scrollHeight - scrollTop - clientHeight < 40
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
