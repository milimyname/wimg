<script lang="ts">
  import "../app.css";
  import { onMount } from "svelte";

  let { children } = $props();

  onMount(() => {
    document.body.classList.add("ready");
  });
</script>

{@render children()}
