/**
 * Command Palette reactive store — controls overlay open state and search query.
 */

let open = $state(false);
let query = $state("");
let selectedIndex = $state(0);

export const paletteStore = {
  get open() {
    return open;
  },
  set open(v: boolean) {
    open = v;
    if (!v) {
      query = "";
      selectedIndex = 0;
    }
  },
  get query() {
    return query;
  },
  set query(v: string) {
    query = v;
    selectedIndex = 0;
  },
  get selectedIndex() {
    return selectedIndex;
  },
  set selectedIndex(v: number) {
    selectedIndex = v;
  },
  toggle() {
    paletteStore.open = !open;
  },
  show() {
    paletteStore.open = true;
  },
  hide() {
    paletteStore.open = false;
  },
};
