/**
 * Reactive toast store for undo snackbar.
 */

let visible = $state(false);
let message = $state("");
let undoCallback: (() => Promise<void>) | null = $state(null);
let timer: ReturnType<typeof setTimeout> | null = null;

export const toastStore = {
  get visible() {
    return visible;
  },
  get message() {
    return message;
  },
  get hasUndo() {
    return undoCallback !== null;
  },

  show(msg: string, onUndo?: () => Promise<void>) {
    if (timer) clearTimeout(timer);
    message = msg;
    undoCallback = onUndo ?? null;
    visible = true;
    timer = setTimeout(() => {
      toastStore.dismiss();
    }, 5000);
  },

  dismiss() {
    if (timer) clearTimeout(timer);
    timer = null;
    visible = false;
    undoCallback = null;
  },

  async triggerUndo() {
    if (!undoCallback) return;
    const cb = undoCallback;
    toastStore.dismiss();
    await cb();
  },
};
