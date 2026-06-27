// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

const applyStoredTheme = () => {
  document.documentElement.classList.toggle("dark", window.localStorage.getItem("flightwatch-theme") === "dark")
}

applyStoredTheme()
document.addEventListener("turbo:load", applyStoredTheme)
