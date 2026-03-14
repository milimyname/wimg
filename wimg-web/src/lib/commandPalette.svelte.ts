/**
 * Command Palette reactive store — controls overlay open state and search query.
 */

class PaletteStore {
  #open = $state(false);
  #query = $state("");
  #selectedIndex = $state(0);

  get open() {
    return this.#open;
  }

  set open(v: boolean) {
    this.#open = v;
    if (!v) {
      this.#query = "";
      this.#selectedIndex = 0;
    }
  }

  get query() {
    return this.#query;
  }

  set query(v: string) {
    this.#query = v;
    this.#selectedIndex = 0;
  }

  get selectedIndex() {
    return this.#selectedIndex;
  }

  set selectedIndex(v: number) {
    this.#selectedIndex = v;
  }

  toggle() {
    this.open = !this.#open;
  }

  show() {
    this.open = true;
  }

  hide() {
    this.open = false;
  }
}

export const paletteStore = new PaletteStore();
