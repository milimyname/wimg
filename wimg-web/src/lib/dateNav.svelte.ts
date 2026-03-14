/**
 * Global month/year navigation store — shared between dashboard, analysis, review.
 * Command Palette actions can navigate months via this store.
 */

const now = new Date();

class DateNavStore {
  #year = $state(now.getFullYear());
  #month = $state(now.getMonth() + 1);

  get year() {
    return this.#year;
  }

  set year(v: number) {
    this.#year = v;
  }

  get month() {
    return this.#month;
  }

  set month(v: number) {
    this.#month = v;
  }

  prev() {
    if (this.#month === 1) {
      this.#month = 12;
      this.#year -= 1;
    } else {
      this.#month -= 1;
    }
  }

  next() {
    if (this.#month === 12) {
      this.#month = 1;
      this.#year += 1;
    } else {
      this.#month += 1;
    }
  }

  goTo(year: number, month: number) {
    this.#year = year;
    this.#month = month;
  }

  reset() {
    const n = new Date();
    this.#year = n.getFullYear();
    this.#month = n.getMonth() + 1;
  }
}

export const dateNav = new DateNavStore();
