<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import CategoryBadge from "./CategoryBadge.svelte";

  let {
    txn,
    onCategoryClick,
  }: {
    txn: Transaction;
    onCategoryClick?: (id: string) => void;
  } = $props();

  function formatAmount(amount: number): string {
    return new Intl.NumberFormat("de-DE", {
      style: "currency",
      currency: "EUR",
    }).format(amount);
  }
</script>

<div class="flex items-center gap-3 p-4">
  <CategoryBadge
    category={txn.category}
    onclick={onCategoryClick ? () => onCategoryClick!(txn.id) : undefined}
  />
  <div class="flex-1 min-w-0">
    <p class="text-sm font-medium truncate">{txn.description}</p>
    <p class="text-xs text-(--color-text-secondary)">
      {CATEGORIES[txn.category]?.name ?? "Unknown"}
    </p>
  </div>
  <span
    class="text-sm font-semibold tabular-nums"
    class:text-green-600={txn.amount > 0}
    class:text-red-600={txn.amount < 0}
  >
    {formatAmount(txn.amount)}
  </span>
</div>
