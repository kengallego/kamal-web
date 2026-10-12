import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "group", "empty", "count"]

  connect() {
    this.filter()
  }

  filter() {
    const normalize = value => value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLocaleLowerCase()
    const query = normalize(this.inputTarget.value.trim())
    let count = 0
    this.itemTargets.forEach(item => {
      const matches = normalize(item.dataset.filterText || item.textContent).includes(query)
      item.hidden = !matches
      if (matches) count++
    })
    this.groupTargets.forEach(group => {
      group.hidden = !Array.from(group.querySelectorAll('[data-filter-target~="item"]')).some(item => !item.hidden)
    })
    this.emptyTarget.hidden = count !== 0
    this.countTargets.forEach(target => { target.textContent = count })
  }
}
