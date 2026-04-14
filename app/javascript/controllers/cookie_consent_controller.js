import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["banner"]

  connect() {
    if (this.hasConsent()) {
      this.loadAnalytics()
      this.hideBanner()
    } else {
      this.showBanner()
    }
  }

  accept() {
    localStorage.setItem("cookie_consent", "accepted")
    this.loadAnalytics()
    this.hideBanner()
  }

  reject() {
    localStorage.setItem("cookie_consent", "rejected")
    this.hideBanner()
  }

  hasConsent() {
    return localStorage.getItem("cookie_consent") === "accepted"
  }

  showBanner() {
    this.bannerTarget.classList.remove("hidden")
  }

  hideBanner() {
    this.bannerTarget.classList.add("hidden")
  }

  loadAnalytics() {
    if (window.gaLoaded) return
    window.gaLoaded = true

    const script = document.createElement("script")
    script.async = true
    script.src = "https://www.googletagmanager.com/gtag/js?id=G-T4PQ0PR817"
    document.head.appendChild(script)

    window.dataLayer = window.dataLayer || []
    function gtag() { window.dataLayer.push(arguments) }
    window.gtag = gtag
    gtag("js", new Date())
    gtag("config", "G-T4PQ0PR817")
  }
}
