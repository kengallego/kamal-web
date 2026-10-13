import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"

function controller(name, globals = {}) {
  const source = readFileSync(new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url), "utf8")
    .replace(/^import .*$/m, "")
    .replace("export default class", "globalThis.Subject = class")
  const context = { Controller: class {}, setTimeout, clearTimeout, ...globals }
  runInNewContext(source, context)
  return new context.Subject()
}

function confirmation() {
  const callbacks = []
  const instance = controller("typed_confirm", {
    window: { Turbo: { config: { forms: {} } } },
    document: { createElement: () => ({}) }
  })
  instance.element = {
    open: false,
    showModal() { this.open = true },
    querySelector: () => ({ focus() {} }),
    addEventListener: (_, callback) => callbacks.push(callback),
    close(value) {
      this.returnValue = value
      this.open = false
      callbacks.splice(0).forEach(callback => callback())
    }
  }
  instance.messageTarget = {}
  instance.wordTarget = {}
  instance.challengeTarget = {}
  instance.inputTarget = { value: "", focus() {} }
  instance.confirmTarget = {}
  instance.connect()
  const form = {
    dataset: {}, inputs: [], submissions: 0,
    querySelector: () => null,
    append(input) { this.inputs.push(input) },
    requestSubmit() { this.submissions++ }
  }
  return { instance, form }
}

test("ordinary confirmations wait for a choice and cancel safely", async () => {
  const { instance, form } = confirmation()
  const pending = instance.ask("Restart application?", form)
  assert.equal(instance.element.open, true)
  assert.equal(instance.challengeTarget.hidden, true)
  instance.element.close("cancel")
  assert.equal(await pending, false)
  assert.equal(form.submissions, 0)
  const accepted = instance.ask("Restart application?", form)
  instance.element.close("confirm")
  assert.equal(await accepted, true)
})

test("protected destinations require the exact word before rebuilding the submission", async () => {
  const { instance, form } = confirmation()
  form.dataset.confirmationWord = "production"
  assert.equal(await instance.ask("Deploy?", form), false)
  assert.equal(instance.confirmTarget.disabled, true)
  instance.inputTarget.value = "Production"
  instance.check()
  assert.equal(instance.confirmTarget.disabled, true)
  instance.inputTarget.value = "production"
  instance.check()
  assert.equal(instance.confirmTarget.disabled, false)
  instance.element.close("confirm")
  assert.equal(form.submissions, 1)
  assert.equal(form.inputs[0].name, "confirmation")
  assert.equal(form.inputs[0].value, "production")
  assert.equal(await instance.ask("Deploy?", form), true)
  assert.equal(form.dataset.confirmed, undefined)
})

test("canceling a protected action never adds a confirmation or submits", async () => {
  const { instance, form } = confirmation()
  form.dataset.confirmationWord = "production"
  await instance.ask("Deploy?", form)
  instance.element.close("")
  assert.equal(form.inputs.length, 0)
  assert.equal(form.submissions, 0)
})

test("navigation cancels pending confirmations", async () => {
  const { instance, form } = confirmation()
  const pending = instance.ask("Restart?", form)
  instance.disconnect()
  assert.equal(await pending, false)
})

test("search handles accents, empty results and clearing the query", () => {
  const instance = controller("filter")
  instance.inputTarget = { value: "monitorizacion" }
  instance.itemTargets = [
    { dataset: { filterText: "Monitorización" } },
    { dataset: { filterText: "Desplegar" } }
  ]
  instance.groupTargets = instance.itemTargets.map(item => ({ querySelectorAll: () => [item] }))
  instance.emptyTarget = {}
  instance.countTargets = [{}]
  instance.filter()
  assert.equal(instance.itemTargets[0].hidden, false)
  assert.equal(instance.itemTargets[1].hidden, true)
  assert.equal(instance.groupTargets[1].hidden, true)
  assert.equal(instance.countTargets[0].textContent, 1)
  instance.inputTarget.value = "unknown"
  instance.filter()
  assert.equal(instance.emptyTarget.hidden, false)
  instance.inputTarget.value = ""
  instance.filter()
  assert.equal(instance.countTargets[0].textContent, 2)
  assert.equal(instance.emptyTarget.hidden, true)
})
