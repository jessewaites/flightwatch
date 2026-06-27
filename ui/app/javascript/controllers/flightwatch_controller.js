import { Controller } from "@hotwired/stimulus"

const PLANE_PATH = "M511.06,286.261c-0.387-10.849-7.42-20.615-18.226-25.356l-193.947-74.094C298.658,78.15,285.367,3.228,256.001,3.228c-29.366,0-42.657,74.922-42.885,183.583L19.167,260.904C8.345,265.646,1.33,275.412,0.941,286.261L0.008,311.97c-0.142,3.886,1.657,7.623,4.917,10.188c3.261,2.564,7.597,3.684,11.845,3.049c0,0,151.678-22.359,198.037-29.559c1.85,82.016,4.019,127.626,4.019,127.626l-51.312,24.166c-6.046,2.38-10.012,8.206-10.012,14.701v9.465c0,4.346,1.781,8.505,4.954,11.493c3.155,2.987,7.403,4.539,11.74,4.292l64.83-3.667c2.08,14.436,8.884,25.048,16.975,25.048c8.091,0,14.877-10.612,16.975-25.048l64.832,3.667c4.336,0.246,8.584-1.305,11.738-4.292c3.174-2.988,4.954-7.148,4.954-11.493v-9.465c0-6.495-3.966-12.321-10.012-14.701l-51.329-24.166c0,0,2.186-45.61,4.037-127.626c46.358,7.2,198.036,29.559,198.036,29.559c4.248,0.635,8.602-0.485,11.845-3.049c3.261-2.565,5.041-6.302,4.918-10.188L511.06,286.261z"

export default class extends Controller {
  static targets = ["map", "panel", "banner", "themeIcon", "realtimeButton", "demoButton"]
  static values = {
    frame: Object,
    flags: Array,
    verdicts: Array,
    situations: Array,
    mode: String
  }

  connect() {
    this.overviewCenter = [42.3656, -71.0096]
    this.overviewZoom = 10
    this.closeZoom = 12
    this.markers = new Map()
    this.flags = new Map()
    this.verdicts = new Map()
    this.focusIcao = null

    this.flagsValue.forEach((flag) => this.flags.set(this.key(flag.icao24, flag.ts), flag))
    this.verdictsValue.forEach((verdict) => this.verdicts.set(this.key(verdict.icao24, verdict.flag_ts), verdict))

    this.initTheme()
    this.initMode()
    this.initMap()
    this.connectCable()
  }

  disconnect() {
    if (this.socket) this.socket.close()
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab

    this.element.querySelectorAll(".tab").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === tab)
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("is-active", panel.dataset.panel === tab)
    })

    if (tab === "map" && this.map) {
      window.requestAnimationFrame(() => this.map.invalidateSize())
    }
  }

  toggleDark() {
    const enabled = !document.documentElement.classList.contains("dark")
    this.setDark(enabled)
  }

  setRealtime() {
    this.setMode("realtime")
  }

  setDemo() {
    this.setMode("demo")
  }

  initTheme() {
    const stored = window.localStorage.getItem("flightwatch-theme")
    this.setDark(stored === "dark")
  }

  setDark(enabled) {
    document.documentElement.classList.toggle("dark", enabled)
    window.localStorage.setItem("flightwatch-theme", enabled ? "dark" : "light")
    this.themeIconTarget.textContent = enabled ? "L" : "D"

    if (!this.map) return

    if (this.tileLayer) this.map.removeLayer(this.tileLayer)
    this.tileLayer = enabled ? this.darkTiles() : this.lightTiles()
    this.tileLayer.addTo(this.map)
  }

  initMode() {
    this.updateModeButtons(this.modeValue || "demo")
  }

  setMode(source) {
    this.updateModeButtons(source)

    fetch("/mode", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ source })
    }).catch(() => this.updateModeButtons(this.modeValue || "demo"))
  }

  updateModeButtons(source) {
    this.modeValue = source
    this.realtimeButtonTarget.classList.toggle("is-active", source === "realtime")
    this.demoButtonTarget.classList.toggle("is-active", source === "demo")
  }

  initMap() {
    if (!window.L) return

    this.map = L.map(this.mapTarget, {
      zoomControl: true,
      preferCanvas: true
    }).setView(this.overviewCenter, this.overviewZoom)

    this.tileLayer = document.documentElement.classList.contains("dark") ? this.darkTiles() : this.lightTiles()
    this.tileLayer.addTo(this.map)

    this.addAirport()
    this.renderFrame(this.frameValue)
    window.requestAnimationFrame(() => this.map.invalidateSize())
  }

  lightTiles() {
    return L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: "&copy; OpenStreetMap contributors"
    })
  }

  darkTiles() {
    return L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
      maxZoom: 19,
      attribution: "&copy; OpenStreetMap contributors &copy; CARTO"
    })
  }

  addAirport() {
    const icon = L.divIcon({
      className: "",
      html: "<div class=\"airport-marker\">KBOS</div>",
      iconSize: [38, 38],
      iconAnchor: [19, 19]
    })
    L.marker(this.overviewCenter, { icon, interactive: false }).addTo(this.map)
  }

  renderFrame(frame) {
    if (!frame || !Array.isArray(frame.aircraft)) return

    frame.aircraft.forEach((plane) => {
      if (!plane.lat || !plane.lon) return

      const marker = this.markers.get(plane.icao24)
      const icon = this.planeIcon(plane)
      const position = [plane.lat, plane.lon]

      if (marker) {
        marker.setLatLng(position)
        marker.setIcon(icon)
      } else {
        const next = L.marker(position, { icon }).addTo(this.map)
        next.bindTooltip(plane.callsign || plane.icao24, { direction: "top", opacity: 0.92 })
        this.markers.set(plane.icao24, next)
      }
    })
  }

  planeIcon(plane) {
    const heading = plane.true_track ?? plane.heading ?? 0
    const state = this.planeState(plane)
    const label = state === "flagged" || state === "focus"
      ? `<span class="plane-label">${this.escapeHtml(plane.callsign || plane.icao24)}</span>`
      : ""

    return L.divIcon({
      className: "",
      html: `<div class="plane-marker ${state}" style="transform: rotate(${heading}deg)"><svg viewBox="0 0 512 512" aria-hidden="true"><path d="${PLANE_PATH}"></path></svg></div>${label}`,
      iconSize: [42, 48],
      iconAnchor: [21, 21]
    })
  }

  planeState(plane) {
    if (plane.on_ground) return "ground"
    if (this.focusIcao === plane.icao24) return "focus"
    if (plane.state === "flagged" || this.flagFor(plane.icao24)) return "flagged"
    return "normal"
  }

  connectCable() {
    const protocol = window.location.protocol === "https:" ? "wss" : "ws"
    this.socket = new WebSocket(`${protocol}://${window.location.host}/cable`)

    this.socket.addEventListener("open", () => {
      this.socket.send(JSON.stringify({
        command: "subscribe",
        identifier: JSON.stringify({ channel: "AirspaceChannel" })
      }))
    })

    this.socket.addEventListener("message", (event) => {
      const data = JSON.parse(event.data)
      if (data.message) this.handleMessage(data.message)
    })
  }

  handleMessage(message) {
    if (message.type === "frame") this.handleFrame(message.frame)
    if (message.type === "flag") this.handleFlag(message.flag, message.frame)
    if (message.type === "verdict") this.handleVerdict(message.verdict)
    if (message.type === "situation") this.handleSituation(message.situation)
    if (message.type === "mode") this.updateModeButtons(message.mode)
  }

  handleFrame(frame) {
    if (!frame) return
    this.frameValue = frame
    this.renderFrame(frame)
  }

  handleFlag(flag, frame) {
    this.flags.set(this.key(flag.icao24, flag.ts), flag)
    this.focusIcao = flag.icao24

    if (frame) {
      this.frameValue = frame
      this.renderFrame(frame)
    }

    if (flag.lat && flag.lon) {
      this.map.flyTo([flag.lat, flag.lon], this.closeZoom, { duration: 1.1 })
    }
  }

  handleVerdict(verdict) {
    this.verdicts.set(this.key(verdict.icao24, verdict.flag_ts), verdict)
    this.focusIcao = verdict.icao24
    this.renderFrame(this.frameValue)

    const marker = this.markers.get(verdict.icao24)
    if (marker) {
      marker.bindPopup(`<strong>${this.escapeHtml(verdict.assessment || "Verdict")}</strong><br>${this.escapeHtml(verdict.summary || "")}`).openPopup()
    }

    window.setTimeout(() => {
      this.focusIcao = null
      this.renderFrame(this.frameValue)
      this.map.flyTo(this.overviewCenter, this.overviewZoom, { duration: 1.2 })
    }, 1500)
  }

  handleSituation(situation) {
    this.bannerTarget.classList.add("is-visible")
    this.bannerTarget.innerHTML = `<strong>${this.escapeHtml(this.humanize(situation.kind))} at ${this.escapeHtml(situation.airport || "KBOS")}</strong><span>${this.escapeHtml(situation.summary || "")}</span>`
  }

  flagFor(icao24) {
    return Array.from(this.flags.values()).find((flag) => flag.icao24 === icao24)
  }

  key(icao24, ts) {
    return `${icao24}-${ts}`
  }

  humanize(value) {
    return String(value || "").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase())
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value == null ? "" : String(value)
    return div.innerHTML
  }
}
