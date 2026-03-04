<script lang="ts">
  import type { Snippet } from "svelte";
  import type { Attachment } from "svelte/attachments";
  import { Spring } from "svelte/motion";

  interface Props {
    open: boolean;
    onclose: () => void;
    snaps?: number[];
    children: Snippet<
      [{ content: Attachment; handle: Attachment; height: number }]
    >;
  }

  let { open, onclose, snaps, children }: Props = $props();

  // Snap points as fractions of viewport height
  const getSnaps = () => {
    const vh = window.innerHeight;
    if (snaps) return [0, ...snaps.map((s) => vh * s)];
    return [0, vh * 0.55, vh * 0.88];
  };

  const height = new Spring(0, { stiffness: 0.15, damping: 0.82 });

  let portalEl: HTMLDivElement | undefined = $state();
  let sheetRef: HTMLElement | undefined = $state();
  let contentRef: HTMLElement | undefined = $state();
  let handleRef: HTMLElement | undefined = $state();
  let isDragging = $state(false);

  // Touch state
  let startY = 0;
  let startHeight = 0;
  let lastY = 0;
  let lastTime = 0;
  let velocity = 0;
  let isDraggingSheet = false;

  // Wheel state
  let snapTimer: ReturnType<typeof setTimeout>;

  const isVisible = $derived(height.current > 5);
  const isExpanded = $derived.by(() => {
    const s = getSnaps();
    return height.current >= (s[s.length - 1] ?? 600) - 10;
  });

  // Progress 0→1 as sheet rises to medium snap (drives background transform)
  const progress = $derived.by(() => {
    const s = getSnaps();
    const mid = s[1] ?? 300;
    return Math.min(1, Math.max(0, height.current / mid));
  });

  // Portal: move sheet container to document.body so it's outside the transformed page
  $effect(() => {
    if (portalEl && portalEl.parentNode !== document.body) {
      document.body.appendChild(portalEl);
    }
    return () => {
      portalEl?.remove();
    };
  });

  // Drive background transform via CSS custom property
  $effect(() => {
    document.documentElement.style.setProperty(
      "--sheet-progress",
      String(progress),
    );

    if (progress > 0.01) {
      document.documentElement.classList.add("sheet-active");
    } else {
      document.documentElement.classList.remove("sheet-active");
    }

    return () => {
      document.documentElement.style.removeProperty("--sheet-progress");
      document.documentElement.classList.remove("sheet-active");
    };
  });

  // Open/close reactivity
  $effect(() => {
    if (open) {
      const s = getSnaps();
      height.target = s[1]; // medium snap
    } else {
      height.target = 0;
    }
  });

  // Lock body scroll when visible
  $effect(() => {
    if (isVisible) {
      const orig = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = orig;
      };
    }
  });

  // Lock content scroll while dragging
  $effect(() => {
    if (contentRef) {
      contentRef.style.overflowY = isDragging ? "hidden" : "auto";
    }
  });

  // Close when spring settles near 0 after being open
  $effect(() => {
    if (open && height.current < 15 && !isDragging && height.target === 0) {
      onclose();
    }
  });

  // Click outside to close (delayed by one frame to skip the opening click)
  $effect(() => {
    if (!open) return;

    function onClickOutside(event: MouseEvent) {
      const target = event.target as Node;
      if (!document.contains(target)) return;
      if (sheetRef && !sheetRef.contains(target)) {
        height.target = 0;
      }
    }

    const frame = requestAnimationFrame(() => {
      document.addEventListener("click", onClickOutside);
    });
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("click", onClickOutside);
    };
  });

  // Escape key
  function onKeydown(e: KeyboardEvent) {
    if (e.key === "Escape" && open) {
      height.target = 0;
    }
  }

  // Attachments
  const onSheet: Attachment = (node) => {
    const el = node as HTMLElement;
    sheetRef = el;
    el.addEventListener("touchstart", onTouchStart, { passive: false });
    el.addEventListener("touchmove", onTouchMove, { passive: false });
    el.addEventListener("touchend", onTouchEnd);
    return () => {
      el.removeEventListener("touchstart", onTouchStart);
      el.removeEventListener("touchmove", onTouchMove);
      el.removeEventListener("touchend", onTouchEnd);
      sheetRef = undefined;
    };
  };

  const onContent: Attachment = (node) => {
    const el = node as HTMLElement;
    contentRef = el;
    el.style.overflowY = "auto";
    el.style.overscrollBehavior = "contain";
    el.style.touchAction = "pan-y";
    return () => {
      contentRef = undefined;
    };
  };

  const onHandle: Attachment = (node) => {
    const el = node as HTMLElement;
    handleRef = el;
    el.style.touchAction = "none";
    el.style.cursor = "grab";
    return () => {
      handleRef = undefined;
    };
  };

  // Wheel handler (desktop scroll control)
  function onWheel(e: WheelEvent) {
    if (contentRef && contentRef.contains(e.target as Node) && isExpanded) {
      const isScrollable = contentRef.scrollHeight > contentRef.clientHeight;
      if (isScrollable) {
        const isAtTop = contentRef.scrollTop <= 0;
        const isScrollingDown = e.deltaY > 0;
        if (!isAtTop || isScrollingDown) return;
      }
    }

    isDragging = true;
    isDraggingSheet = true;
    clearTimeout(snapTimer);

    const s = getSnaps();
    const maxSnap = s[s.length - 1];
    const newTarget = Math.max(-20, Math.min(maxSnap + 50, height.target - e.deltaY));
    height.target = newTarget;

    snapTimer = setTimeout(() => {
      performSnap();
      isDragging = false;
      isDraggingSheet = false;
    }, 100);
  }

  // Touch handlers
  function onTouchStart(e: TouchEvent) {
    startY = e.touches[0].clientY;
    lastY = startY;
    lastTime = Date.now();
    velocity = 0;
    startHeight = height.current;
    isDragging = true;
    isDraggingSheet = false;

    const isHandle = handleRef?.contains(e.target as Node);
    const isContent = contentRef?.contains(e.target as Node);

    if (isHandle) {
      // Handle always controls the sheet
      isDraggingSheet = true;
    } else if (!isContent) {
      // Touch outside both handle and content → sheet drag
      isDraggingSheet = true;
    }
    // Content touches: let scroll happen, onTouchMove takes over only at boundaries
  }

  function onTouchMove(e: TouchEvent) {
    const currentY = e.touches[0].clientY;
    const currentTime = Date.now();
    const deltaY = startY - currentY;

    const timeDelta = currentTime - lastTime;
    if (timeDelta > 0) {
      velocity = (lastY - currentY) / timeDelta;
    }
    lastY = currentY;
    lastTime = currentTime;

    // Hand off from content scroll → sheet drag at boundaries
    if (!isDraggingSheet && contentRef) {
      const isScrollable =
        contentRef.scrollHeight > contentRef.clientHeight + 1;
      const isAtTop = contentRef.scrollTop <= 1;
      const isAtBottom =
        contentRef.scrollTop >=
        contentRef.scrollHeight - contentRef.clientHeight - 1;
      const isPullingDown = deltaY < -2;
      const isPullingUp = deltaY > 2;

      // Pull down at top → shrink/close sheet
      if (isAtTop && isPullingDown) {
        isDraggingSheet = true;
      }
      // Pull up when content can't scroll (or at bottom) → expand sheet
      if (isPullingUp && (!isScrollable || isAtBottom)) {
        isDraggingSheet = true;
      }
    }

    if (isDraggingSheet) {
      if (e.cancelable) e.preventDefault();
      const s = getSnaps();
      const maxSnap = s[s.length - 1];
      const newHeight = Math.max(
        -20,
        Math.min(maxSnap + 50, startHeight + deltaY),
      );
      height.target = newHeight;
    }
  }

  function onTouchEnd() {
    performSnap();
    isDragging = false;
    isDraggingSheet = false;
    velocity = 0;
  }

  function performSnap() {
    const current = height.current;
    const s = getSnaps();
    const sortedSnaps = [...s].sort((a, b) => a - b);
    const minSnap = sortedSnaps[0];
    const maxSnap = sortedSnaps[sortedSnaps.length - 1];
    const velocityThreshold = 0.4;

    let targetSnap: number;

    if (Math.abs(velocity) > velocityThreshold) {
      if (velocity > 0) {
        targetSnap =
          sortedSnaps.find((snap) => snap > current) ?? maxSnap;
      } else {
        targetSnap =
          [...sortedSnaps].reverse().find((snap) => snap < current) ??
          minSnap;
      }
    } else {
      targetSnap = sortedSnaps.reduce((prev, curr) =>
        Math.abs(curr - current) < Math.abs(prev - current) ? curr : prev,
      );
    }

    height.target = targetSnap;
  }
</script>

<svelte:window on:keydown={onKeydown} />

<!-- Portal container: moved to document.body -->
<div bind:this={portalEl} class="sheet-portal">
  {#if open || isVisible}
    <div
      class="sheet-root"
      style:height="{Math.max(0, height.current)}px"
      style:visibility={isVisible ? "visible" : "hidden"}
      {@attach onSheet}
      onwheel={onWheel}
      role="dialog"
      aria-modal="true"
    >
      {@render children({
        content: onContent,
        handle: onHandle,
        height: height.current,
      })}
    </div>
  {/if}
</div>

<style>
  .sheet-portal {
    /* Portal container — lives on document.body */
  }

  .sheet-root {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    max-width: 42rem;
    margin: 0 auto;
    background: white;
    border-radius: 20px 20px 0 0;
    box-shadow: 0 -4px 30px rgba(0, 0, 0, 0.08);
    display: flex;
    flex-direction: column;
    will-change: height;
    z-index: 40;
    overflow: hidden;
  }
</style>
