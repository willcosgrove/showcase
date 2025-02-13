import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="people-search"
export default class extends Controller {
  connect() {
    this.element.addEventListener('input', event => {
      let input = this.element.value.toLowerCase();
      let tokens = input.trim().split(' ');
      for (let row of document.querySelectorAll('tbody tr')) {
        let name = row.querySelector('td').textContent.toLowerCase();
        if (!input || tokens.every(token => name.includes(token))) {
          row.style.display = 'table-row';
        } else {
          row.style.display = 'none';
        }
      }
    });

    this.element.focus();
  }
}

document.body.parentNode.addEventListener('keydown', event => {
  if (event.key != 'Escape') return;

  if (document.querySelectorAll('input[type=text], textarea, select').length != 0) return;

  let home = document.querySelector('a[rel=home]');
  if (!home) return;

  Turbo.visit(home.href + 'people/');
});