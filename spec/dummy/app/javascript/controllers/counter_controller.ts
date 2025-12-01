import { Controller } from "@hotwired/stimulus";

// Counter controller for testing Stimulus alongside React counters
export default class CounterController extends Controller<HTMLElement> {
  static targets = ["count"];
  static values = { count: { type: Number, default: 0 } };
  
  declare countTarget: HTMLElement;
  declare hasCountTarget: boolean;
  declare countValue: number;

  connect() {
    console.log("[Stimulus] CounterController connected");
    this.updateDisplay();
  }

  increment() {
    this.countValue++;
    this.updateDisplay();
  }

  decrement() {
    this.countValue--;
    this.updateDisplay();
  }

  reset() {
    this.countValue = 0;
    this.updateDisplay();
  }

  updateDisplay() {
    if (this.hasCountTarget) {
      this.countTarget.textContent = String(this.countValue);
    }
  }

  disconnect() {
    console.log("[Stimulus] CounterController disconnected");
  }
}


