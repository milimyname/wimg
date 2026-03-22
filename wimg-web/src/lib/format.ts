/**
 * Shared formatting utilities for wimg-web.
 * Locale-aware: reads current locale from localStorage.
 */

import { LS_LOCALE } from "$lib/config";

export function localeTag(): string {
  if (typeof localStorage === "undefined") return "de-DE";
  const loc = localStorage.getItem(LS_LOCALE) ?? "de";
  return loc === "en" ? "en-US" : "de-DE";
}

function eurFormatter(): Intl.NumberFormat {
  return new Intl.NumberFormat(localeTag(), {
    style: "currency",
    currency: "EUR",
  });
}

function eurSignedFormatter(): Intl.NumberFormat {
  return new Intl.NumberFormat(localeTag(), {
    style: "currency",
    currency: "EUR",
    signDisplay: "always",
  });
}

export function formatEur(amount: number): string {
  return eurFormatter().format(amount);
}

/** Compact format for tight spaces: 2616 → "2,6k €", 999 → "999 €" */
export function formatEurCompact(amount: number): string {
  const abs = Math.abs(amount);
  if (abs >= 1000) {
    const sep = localeTag() === "en-US" ? "." : ",";
    const k = (abs / 1000).toFixed(1).replace(".", sep);
    return `${k}k €`;
  }
  return eurFormatter().format(amount);
}

export function formatAmountSigned(amount: number): string {
  return eurSignedFormatter().format(amount);
}

export function formatDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString(localeTag(), {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function formatDateShort(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString(localeTag(), { day: "2-digit", month: "short" });
}

export function formatDateHeading(dateStr: string): string {
  const tag = localeTag();
  const date = new Date(dateStr + "T00:00:00");
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  const day = date.getDate();
  const month = date.toLocaleDateString(tag, { month: "long" });
  const yearSuffix = date.getFullYear() !== today.getFullYear() ? ` ${date.getFullYear()}` : "";

  const todayLabel = tag === "en-US" ? "Today" : "Heute";
  const yesterdayLabel = tag === "en-US" ? "Yesterday" : "Gestern";

  if (date.toDateString() === today.toDateString()) return `${todayLabel} · ${day}. ${month}`;
  if (date.toDateString() === yesterday.toDateString())
    return `${yesterdayLabel} · ${day}. ${month}`;

  const weekday = date.toLocaleDateString(tag, { weekday: "long" });
  return `${weekday} · ${day}. ${month}${yearSuffix}`;
}
