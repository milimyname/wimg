let pendingFile = $state<File | null>(null);

export const dropStore = {
  get file() {
    return pendingFile;
  },
  set(file: File) {
    pendingFile = file;
  },
  clear() {
    pendingFile = null;
  },
};
