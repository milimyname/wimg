<script lang="ts">
  import { CATEGORIES, type Transaction } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import CategoryBadge from "./CategoryBadge.svelte";

  let {
    txn,
    onCategoryClick,
  }: {
    txn: Transaction;
    onCategoryClick?: (id: string) => void;
  } = $props();
</script>

<div class="flex items-center gap-3.5 p-4">
  <CategoryBadge
    category={txn.category}
    onclick={onCategoryClick ? () => onCategoryClick!(txn.id) : undefined}
  />
  <div class="flex-1 min-w-0">
    <p class="text-sm font-bold truncate">{txn.description}</p>
    <p class="text-xs text-(--color-text-secondary) mt-0.5">
      {CATEGORIES[txn.category]?.name ?? "Unknown"}
    </p>
  </div>
  <span
    class="text-sm font-extrabold tabular-nums"
    class:text-emerald-600={txn.amount > 0}
  >
    {formatEur(txn.amount)}
  </span>
</div>
