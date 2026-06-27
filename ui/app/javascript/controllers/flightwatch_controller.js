import { Controller } from "@hotwired/stimulus"

const PLANE_PATH = "M511.06,286.261c-0.387-10.849-7.42-20.615-18.226-25.356l-193.947-74.094C298.658,78.15,285.367,3.228,256.001,3.228c-29.366,0-42.657,74.922-42.885,183.583L19.167,260.904C8.345,265.646,1.33,275.412,0.941,286.261L0.008,311.97c-0.142,3.886,1.657,7.623,4.917,10.188c3.261,2.564,7.597,3.684,11.845,3.049c0,0,151.678-22.359,198.037-29.559c1.85,82.016,4.019,127.626,4.019,127.626l-51.312,24.166c-6.046,2.38-10.012,8.206-10.012,14.701v9.465c0,4.346,1.781,8.505,4.954,11.493c3.155,2.987,7.403,4.539,11.74,4.292l64.83-3.667c2.08,14.436,8.884,25.048,16.975,25.048c8.091,0,14.877-10.612,16.975-25.048l64.832,3.667c4.336,0.246,8.584-1.305,11.738-4.292c3.174-2.988,4.954-7.148,4.954-11.493v-9.465c0-6.495-3.966-12.321-10.012-14.701l-51.329-24.166c0,0,2.186-45.61,4.037-127.626c46.358,7.2,198.036,29.559,198.036,29.559c4.248,0.635,8.602-0.485,11.845-3.049c3.261-2.565,5.041-6.302,4.918-10.188L511.06,286.261z"
const SUN_ICON = `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="theme-icon"><path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" /></svg>`
const MOON_ICON = `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="theme-icon"><path stroke-linecap="round" stroke-linejoin="round" d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z" /></svg>`

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
    this.trails = new Map()
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
    this.themeIconTarget.innerHTML = enabled ? SUN_ICON : MOON_ICON

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

    const points = []
    frame.aircraft.forEach((plane) => {
      if (!plane.lat || !plane.lon) return

      const marker = this.markers.get(plane.icao24)
      const icon = this.planeIcon(plane)
      const position = [plane.lat, plane.lon]
      const tip = this.planeTooltip(plane)
      points.push(position)

      this.updateTrail(plane, position)

      if (marker) {
        marker.setLatLng(position)
        marker.setIcon(icon)
        marker.setTooltipContent(tip)
      } else {
        const next = L.marker(position, { icon }).addTo(this.map)
        next.bindTooltip(tip, { direction: "top", opacity: 0.95, className: "plane-tooltip" })
        this.markers.set(plane.icao24, next)
      }
    })

    this.maybeFitBounds(points)
  }

  // Frame the map to the planes once on load (and again after a mode toggle): zoomed in enough to
  // show them all with a little padding, but no further. The investigation choreography flies back
  // to this same framing after each verdict.
  maybeFitBounds(points) {
    if (this.hasFitBounds || !this.map || points.length === 0) return

    if (points.length === 1) {
      this.fittedBounds = L.latLng(points[0]).toBounds(8000) // ~8km box around a lone plane
    } else {
      this.fittedBounds = L.latLngBounds(points).pad(0.15)
    }
    this.map.fitBounds(this.fittedBounds, { maxZoom: 12, animate: false })
    this.hasFitBounds = true
  }

  // Accumulate each plane's recent positions (from the frame stream) and draw a dashed trail
  // of where it has been. Flagged planes get a red trail; everyone else a subtle neutral one.
  updateTrail(plane, position) {
    let trail = this.trails.get(plane.icao24)
    if (!trail) {
      trail = { coords: [], line: null }
      this.trails.set(plane.icao24, trail)
    }

    const last = trail.coords[trail.coords.length - 1]
    if (last && last[0] === position[0] && last[1] === position[1]) return // no movement, skip

    trail.coords.push(position)
    if (trail.coords.length > 40) trail.coords.shift() // cap history so it doesn't grow forever
    if (trail.coords.length < 2) return

    const flagged = plane.state === "flagged" || this.flagFor(plane.icao24)
    const color = flagged ? "#ef4444" : "#2563eb"
    const weight = flagged ? 3 : 2

    if (trail.line) {
      trail.line.setLatLngs(trail.coords)
      trail.line.setStyle({ color, weight })
    } else {
      trail.line = L.polyline(trail.coords, {
        color, weight, opacity: 0.7, dashArray: "5 6", interactive: false
      }).addTo(this.map)
    }
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

  // Hover tooltip: the watcher's per-plane telemetry, plus the flag rule if it's flagged.
  planeTooltip(plane) {
    const title = this.escapeHtml((plane.callsign || "").trim() || plane.icao24)
    const num = (v) => v !== null && v !== undefined && v !== "" && !Number.isNaN(Number(v))

    const parts = []
    if (plane.on_ground) parts.push("on ground")
    if (num(plane.baro_alt_ft)) parts.push(`${Math.round(plane.baro_alt_ft).toLocaleString()} ft`)
    if (num(plane.velocity_kt)) parts.push(`${Math.round(plane.velocity_kt)} kt`)
    const hdg = plane.heading ?? plane.true_track
    if (num(hdg)) parts.push(`${Math.round(hdg)}°`)
    if (num(plane.vert_rate_fpm) && Math.round(plane.vert_rate_fpm) !== 0) {
      const vs = Math.round(plane.vert_rate_fpm)
      parts.push(`${vs > 0 ? "+" : ""}${vs.toLocaleString()} fpm`)
    }
    if (plane.squawk) parts.push(`sq ${this.escapeHtml(plane.squawk)}`)

    const flag = this.flagFor(plane.icao24)
    let header = title
    if (plane.state === "flagged" || flag) {
      header = `${title} &mdash; ${this.escapeHtml(flag && flag.rule ? this.humanize(flag.rule) : "Flagged")}`
    }

    return `<div class="plane-tip"><strong>${header}</strong>${parts.length ? `<br><span>${parts.join(" · ")}</span>` : ""}</div>`
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
    if (message.type === "mode") this.handleModeChange(message.mode)
  }

  // A mode switch starts a fresh run (the producer clears the bus), so wipe the stale view:
  // banner, anomalies feed, planes, and trails all reset; new frames/flags repopulate them.
  handleModeChange(mode) {
    this.updateModeButtons(mode)
    this.hasFitBounds = false
    this.focusIcao = null
    this.flags = new Map()
    this.verdicts = new Map()

    this.bannerTarget.classList.remove("is-visible")
    this.bannerTarget.innerHTML = "<strong>Situation watch</strong><span>No synthesized situation yet.</span>"

    const feed = document.getElementById("anomaly-feed")
    if (feed) feed.innerHTML = '<div id="anomaly-empty" class="empty-state">No flags have landed on the bus.</div>'

    this.markers.forEach((marker) => this.map.removeLayer(marker))
    this.markers = new Map()
    this.trails.forEach((trail) => { if (trail.line) this.map.removeLayer(trail.line) })
    this.trails = new Map()
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
      if (this.fittedBounds) {
        this.map.flyToBounds(this.fittedBounds, { maxZoom: 12, duration: 1.2 })
      } else {
        this.map.flyTo(this.overviewCenter, this.overviewZoom, { duration: 1.2 })
      }
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
