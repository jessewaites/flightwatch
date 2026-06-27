// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Apply the saved dark/light theme on every page (incl. the credits page, which has no Stimulus map).
const applyStoredTheme = () => {
  document.documentElement.classList.toggle("dark", window.localStorage.getItem("flightwatch-theme") === "dark")
}

applyStoredTheme()
document.addEventListener("turbo:load", applyStoredTheme)
