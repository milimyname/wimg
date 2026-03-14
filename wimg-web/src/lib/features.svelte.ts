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

class FeatureStore {
  #features = $state(loadFeatures());

  get enabled() {
    return this.#features;
  }

  isEnabled(key: string): boolean {
    return this.#features[key] ?? false;
  }

  toggle(key: string) {
    this.#features = { ...this.#features, [key]: !this.#features[key] };
    saveFeatures(this.#features);
  }

  set(key: string, value: boolean) {
    this.#features = { ...this.#features, [key]: value };
    saveFeatures(this.#features);
  }
}

export const featureStore = new FeatureStore();
