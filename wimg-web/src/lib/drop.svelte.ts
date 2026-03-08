let pendingFiles = $state<File[]>([]);

export const dropStore = {
  get files() {
    return pendingFiles;
  },
  set(files: File[]) {
    pendingFiles = files;
  },
  clear() {
    pendingFiles = [];
  },
};
