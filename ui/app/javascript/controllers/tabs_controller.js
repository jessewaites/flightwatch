import { Controller } from "@hotwired/stimulus"

// Generic tab switcher for static, scrolling pages (e.g. the Evals page's Evals/Tests tabs).
// Distinct from the dashboard's flightwatch#switchTab, which drives absolutely-positioned map panels.
export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const name = event.currentTarget.dataset.tab

    this.tabTargets.forEach((tab) => {
      tab.classList.toggle("is-active", tab.dataset.tab === name)
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("is-active", panel.dataset.tabPanel === name)
    })
  }
}
