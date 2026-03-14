class DropStore {
  #files = $state<File[]>([]);

  get files() {
    return this.#files;
  }

  set(files: File[]) {
    this.#files = files;
  }

  clear() {
    this.#files = [];
  }
}

export const dropStore = new DropStore();
