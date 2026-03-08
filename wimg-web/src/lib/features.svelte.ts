import { LS_FEATURES, DEFAULT_FEATURES } from "./config";

function loadFeatures(): Record<string, boolean> {
  try {
    const stored = localStorage.getItem(LS_FEATURES);
    if (stored) return { ...DEFAULT_FEATURES, ...JSON.parse(stored) };
  } catch {
    // ignore
  }
  return { ...DEFAULT_FEATURES };
}

function saveFeatures(features: Record<string, boolean>) {
  localStorage.setItem(LS_FEATURES, JSON.stringify(features));
}

export const featureStore = (() => {
  let features = $state(loadFeatures());

  return {
    get enabled() {
      return features;
    },
    isEnabled(key: string): boolean {
      return features[key] ?? false;
    },
    toggle(key: string) {
      features = { ...features, [key]: !features[key] };
      saveFeatures(features);
    },
    set(key: string, value: boolean) {
      features = { ...features, [key]: value };
      saveFeatures(features);
    },
  };
})();
