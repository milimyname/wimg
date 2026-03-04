/**
 * Shared formatting utilities for wimg-web.
 */

const eurFmt = new Intl.NumberFormat("de-DE", {
  style: "currency",
  currency: "EUR",
});

const eurSignedFmt = new Intl.NumberFormat("de-DE", {
  style: "currency",
  currency: "EUR",
  signDisplay: "always",
});

export function formatEur(amount: number): string {
  return eurFmt.format(amount);
}

export function formatAmountSigned(amount: number): string {
  return eurSignedFmt.format(amount);
}

export function formatDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString("de-DE", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function formatDateShort(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString("de-DE", { day: "2-digit", month: "short" });
}

export function formatDateHeading(dateStr: string): string {
  const date = new Date(dateStr + "T00:00:00");
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  const day = date.getDate();
  const month = date.toLocaleDateString("de-DE", { month: "long" });

  if (date.toDateString() === today.toDateString())
    return `Heute · ${day}. ${month}`;
  if (date.toDateString() === yesterday.toDateString())
    return `Gestern · ${day}. ${month}`;

  const weekday = date.toLocaleDateString("de-DE", { weekday: "long" });
  return `${weekday} · ${day}. ${month}`;
}
