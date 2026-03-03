export const APP_VERSION = "0.2.0";

export interface ChangelogEntry {
  version: string;
  title: string;
  items: string[];
  breaking: boolean;
}

export const CHANGELOG: ChangelogEntry[] = [
  {
    version: "0.2.0",
    title: "Phase 2: Kernfunktionen",
    items: [
      "Dashboard mit Verfügbarem Einkommen",
      "Ausgabenanalyse mit Donut-Diagramm",
      "Schulden-Tracker mit Fortschrittsbalken",
      "Claude AI Kategorisierung beim Import",
      "PWA — installierbar & offline nutzbar",
    ],
    breaking: false,
  },
];
