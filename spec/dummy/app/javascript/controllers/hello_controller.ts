import { Controller } from "@hotwired/stimulus";

// Simple Stimulus controller for testing coexistence with React
export default class HelloController extends Controller<HTMLElement> {
  static targets = ["output"];
  
  declare outputTarget: HTMLElement;
  declare hasOutputTarget: boolean;

  connect() {
    console.log("[Stimulus] HelloController connected");
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = "Stimulus connected!";
    }
  }

  greet() {
    const name = (this.element.querySelector('[data-name]') as HTMLInputElement)?.value || "World";
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = `Hello, ${name}!`;
      this.outputTarget.dataset.greeted = "true";
    }
  }

  disconnect() {
    console.log("[Stimulus] HelloController disconnected");
  }
}


