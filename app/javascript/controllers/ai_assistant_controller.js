import { Controller } from "@hotwired/stimulus"

// AI Assistant controller for rich text editor integration
// Dispatches actions to the AI Modal controller for streaming responses
export default class extends Controller {
  static targets = ["loading"]

  // Writing Assistant Actions - dispatch to modal for streaming
  improve() {
    this.dispatchToModal("improve")
  }

  summarize() {
    this.dispatchToModal("summarize")
  }

  expand() {
    this.dispatchToModal("expand")
  }

  // Research Actions - dispatch to modal for streaming
  research() {
    this.dispatchToModal("research")
  }

  breakDown() {
    this.dispatchToModal("break_down_task")
  }

  // Dispatch action to the AI Modal controller
  dispatchToModal(actionType) {
    document.dispatchEvent(new CustomEvent("ai-modal:perform", {
      detail: { actionType },
      bubbles: true
    }))
  }
}
