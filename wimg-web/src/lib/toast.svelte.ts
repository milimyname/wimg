/**
 * Reactive toast store for undo snackbar.
 */

class ToastStore {
  #visible = $state(false);
  #message = $state("");
  #undoCallback: (() => Promise<void>) | null = $state(null);
  #timer: ReturnType<typeof setTimeout> | null = null;

  get visible() {
    return this.#visible;
  }

  get message() {
    return this.#message;
  }

  get hasUndo() {
    return this.#undoCallback !== null;
  }

  show(msg: string, onUndo?: () => Promise<void>) {
    if (this.#timer) clearTimeout(this.#timer);
    this.#message = msg;
    this.#undoCallback = onUndo ?? null;
    this.#visible = true;
    this.#timer = setTimeout(() => {
      this.dismiss();
    }, 5000);
  }

  dismiss() {
    if (this.#timer) clearTimeout(this.#timer);
    this.#timer = null;
    this.#visible = false;
    this.#undoCallback = null;
  }

  async triggerUndo() {
    if (!this.#undoCallback) return;
    const cb = this.#undoCallback;
    this.dismiss();
    await cb();
  }
}

export const toastStore = new ToastStore();
