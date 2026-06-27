import { Controller } from "@hotwired/stimulus"

// Generic modal: open() shows the backdrop+card, close() hides it.
// Clicking the backdrop (but not the card) or pressing Escape closes it.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    if (event) event.preventDefault()
    this.dialogTarget.classList.add("is-open")
    document.addEventListener("keydown", this.onKeydown)
  }

  close() {
    this.dialogTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this.onKeydown)
  }

  // Close only when the click lands on the backdrop itself, not its children.
  closeBackdrop(event) {
    if (event.target === event.currentTarget) this.close()
  }

  onKeydown = (event) => {
    if (event.key === "Escape") this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }
}
