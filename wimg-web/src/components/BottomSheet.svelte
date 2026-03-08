<script lang="ts">
  import type { Snippet } from "svelte";
  import type { Attachment } from "svelte/attachments";
  import { Spring } from "svelte/motion";

  interface Props {
    open: boolean;
    onclose: () => void;
    snaps?: number[];
    children: Snippet<
      [{ content: Attachment; handle: Attachment; footer: Attachment; height: number }]
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
  // Footer becomes visible when sheet is past 40% of the first snap
  const footerReady = $derived.by(() => {
    const s = getSnaps();
    const threshold = (s[1] ?? 300) * 0.4;
    return height.current > threshold;
  });

  // Toggle sheet-active class on <html> (used by BottomNav to hide)
  $effect(() => {
    if (open) {
      document.documentElement.classList.add("sheet-active");
      return () => {
        document.documentElement.classList.remove("sheet-active");
      };
    }
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

  // Lock body scroll when visible (iOS PWA needs position:fixed to truly prevent scroll)
  $effect(() => {
    if (isVisible) {
      const scrollY = window.scrollY;
      const origOverflow = document.body.style.overflow;
      const origPosition = document.body.style.position;
      const origTop = document.body.style.top;
      const origWidth = document.body.style.width;
      const origTouchAction = document.body.style.touchAction;

      document.body.style.overflow = "hidden";
      document.body.style.position = "fixed";
      document.body.style.top = `-${scrollY}px`;
      document.body.style.width = "100%";
      document.body.style.touchAction = "none";

      return () => {
        document.body.style.overflow = origOverflow;
        document.body.style.position = origPosition;
        document.body.style.top = origTop;
        document.body.style.width = origWidth;
        document.body.style.touchAction = origTouchAction;
        window.scrollTo(0, scrollY);
      };
    }
  });

  // Close when spring settles near 0 after being open
  $effect(() => {
    if (open && height.current < 15 && !isDragging && height.target === 0) {
      onclose();
    }
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
    el.style.flex = "1";
    el.style.minHeight = "0";
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

  let footerRef: HTMLElement | undefined = $state();

  const onFooter: Attachment = (node) => {
    const el = node as HTMLElement;
    footerRef = el;
    el.style.flexShrink = "0";
    el.style.transition = "opacity 0.3s ease, transform 0.3s ease";
    return () => {
      footerRef = undefined;
    };
  };

  // Animate footer in/out based on sheet height
  $effect(() => {
    if (footerRef) {
      if (footerReady) {
        footerRef.style.opacity = "1";
        footerRef.style.transform = "translateY(0)";
      } else {
        footerRef.style.opacity = "0";
        footerRef.style.transform = "translateY(12px)";
      }
    }
  });

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
      isDraggingSheet = true;
      if (contentRef) contentRef.style.overflowY = "hidden";
    } else if (!isContent) {
      isDraggingSheet = true;
    }
    // Content touches: let native scroll happen, onTouchMove hands off at boundaries
  }

  function takeOverDrag(currentY: number) {
    isDraggingSheet = true;
    // Reset origin to handoff point so the sheet doesn't jump
    startY = currentY;
    startHeight = height.current;
    // Lock content scroll immediately (not via async effect)
    if (contentRef) contentRef.style.overflowY = "hidden";
  }

  function onTouchMove(e: TouchEvent) {
    const currentY = e.touches[0].clientY;
    const currentTime = Date.now();

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

      // Use instantaneous direction (velocity) not overall delta
      // velocity > 0 = finger moving up, velocity < 0 = finger moving down
      if (isAtTop && velocity < -0.05) {
        takeOverDrag(currentY);
      } else if (velocity > 0.05 && (!isScrollable || isAtBottom)) {
        takeOverDrag(currentY);
      }
    }

    if (isDraggingSheet) {
      if (e.cancelable) e.preventDefault();
      const deltaY = startY - currentY;
      const s = getSnaps();
      const maxSnap = s[s.length - 1];
      let newHeight = startHeight + deltaY;

      // Rubber-band past max snap (iOS-style resistance)
      if (newHeight > maxSnap) {
        const overflow = newHeight - maxSnap;
        newHeight = maxSnap + overflow * 0.15;
      }

      height.target = Math.max(-20, newHeight);
    }
  }

  function onTouchEnd() {
    performSnap();
    isDragging = false;
    isDraggingSheet = false;
    velocity = 0;
    // Restore content scrollability
    if (contentRef) contentRef.style.overflowY = "auto";
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

{#if open || isVisible}
  <!-- Backdrop -->
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div
    class="sheet-backdrop"
    onclick={() => (height.target = 0)}
    style:opacity={Math.min(1, height.current / 300) * 0.5}
  ></div>

  <!-- Sheet -->
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
      footer: onFooter,
      height: height.current,
    })}
  </div>
{/if}

<style>
  .sheet-backdrop {
    position: fixed;
    inset: 0;
    background: black;
    z-index: 39;
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
