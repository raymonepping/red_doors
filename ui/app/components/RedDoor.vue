<script setup lang="ts">
// The red door — the one solid, saturated object in a world of glass.
// States: closed · knocking · opening · open · refused · pending.
// One authored motion moment: the swing (rotateY on the hinge, 700ms).
// Refusal is never colour alone: a steel bolt slides across + an aria label.
const props = withDefaults(defineProps<{
  number: number
  method: string
  state?: 'closed' | 'knocking' | 'opening' | 'open' | 'refused' | 'pending'
  size?: 'lg' | 'md' | 'sm'
  title?: string
}>(), { state: 'closed', size: 'md', title: '' })

const label = computed(() => {
  const what = props.title ? `Door ${props.number}, ${props.title}` : `Door ${props.number}`
  const how = {
    closed: 'closed',
    knocking: 'someone is knocking',
    opening: 'opening',
    open: 'open',
    refused: 'refused by Vault — bolted',
    pending: 'waiting for a second person',
  }[props.state]
  return `${what} (${props.method}): ${how}`
})
const uid = useId()
</script>

<template>
  <div class="rd-door" :data-state="state" :data-size="size" role="img" :aria-label="label">
    <div class="rd-door__frame">
      <!-- the lit room behind the door (visible as it swings) -->
      <div class="rd-door__room" aria-hidden="true">
        <slot name="room" />
      </div>

      <div class="rd-door__leaf" aria-hidden="true">
        <svg viewBox="0 0 200 320" class="rd-door__svg" focusable="false">
          <defs>
            <linearGradient :id="`lacq-${uid}`" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stop-color="var(--rd-lacquer-dark)" />
              <stop offset="0.45" stop-color="var(--rd-lacquer)" />
              <stop offset="0.8" stop-color="var(--rd-lacquer-light)" />
              <stop offset="1" stop-color="var(--rd-lacquer)" />
            </linearGradient>
            <linearGradient :id="`sheen-${uid}`" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="var(--rd-lacquer-sheen)" />
              <stop offset="0.35" stop-color="transparent" />
            </linearGradient>
            <linearGradient :id="`brass-${uid}`" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="var(--rd-brass-light)" />
              <stop offset="0.55" stop-color="var(--rd-brass)" />
              <stop offset="1" stop-color="var(--rd-brass-dark)" />
            </linearGradient>
          </defs>

          <!-- leaf -->
          <rect x="2" y="2" width="196" height="316" rx="3" :fill="`url(#lacq-${uid})`" stroke="var(--rd-edge)" stroke-width="3" />
          <!-- recessed panels: upper tall, lower short -->
          <g fill="none" stroke="var(--rd-edge)" stroke-width="2.5" opacity="0.9">
            <rect x="26" y="26" width="148" height="150" rx="2" />
            <rect x="26" y="208" width="148" height="86" rx="2" />
          </g>
          <g fill="none" stroke="var(--rd-lacquer-light)" stroke-width="1.5" opacity="0.7">
            <rect x="33" y="33" width="134" height="136" rx="1.5" />
            <rect x="33" y="215" width="134" height="72" rx="1.5" />
          </g>
          <rect x="2" y="2" width="196" height="316" rx="3" :fill="`url(#sheen-${uid})`" />

          <!-- brass number plate + engraved method -->
          <g class="rd-door__plate">
            <rect x="70" y="72" width="60" height="44" rx="5" :fill="`url(#brass-${uid})`" stroke="var(--rd-brass-dark)" stroke-width="1.5" />
            <text x="100" y="104" text-anchor="middle" class="rd-door__numeral">{{ number }}</text>
          </g>

          <!-- lever handle on the latch side -->
          <g class="rd-door__handle">
            <circle cx="168" cy="190" r="9" :fill="`url(#brass-${uid})`" stroke="var(--rd-brass-dark)" stroke-width="1.5" />
            <rect x="140" y="186" width="30" height="8" rx="4" :fill="`url(#brass-${uid})`" stroke="var(--rd-brass-dark)" stroke-width="1.2" />
          </g>
        </svg>

        <!-- engraved method label (HTML for crisp small text at every size) -->
        <span class="rd-door__method">{{ method }}</span>

        <!-- refused: a steel bolt slides across the latch -->
        <span class="rd-door__bolt" />
        <!-- pending: an amber governance seal -->
        <span class="rd-door__seal">
          <svg viewBox="0 0 24 24" width="100%" height="100%" focusable="false"><path d="M7 11V8a5 5 0 0 1 10 0v3" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" /><rect x="5" y="11" width="14" height="10" rx="2" fill="currentColor" /></svg>
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.rd-door {
  --w: 200px;
  width: var(--w);
  perspective: 1100px;
  flex-shrink: 0;
}
.rd-door[data-size='lg'] { --w: clamp(180px, 22vw, 260px); }
/* In perspective the swung leaf's near edge projects ~10% below the frame;
   reserve that space so it never overlaps what sits underneath. */
.rd-door:not([data-size='sm']) { padding-bottom: calc(var(--w) * 0.14); }
.rd-door[data-size='md'] { --w: 132px; }
.rd-door[data-size='sm'] { --w: 44px; }

/* the doorway: a glass-edged reveal; the room is behind the leaf */
.rd-door__frame {
  position: relative;
  width: 100%;
  border-radius: 6px 6px 2px 2px;
  padding: 6% 6% 0;
  background: var(--rd-doorway);
  box-shadow:
    inset 0 0 0 1px rgba(255, 255, 255, 0.08),
    0 1px 1px rgba(15, 26, 42, 0.06),
    0 18px 34px -16px rgba(15, 26, 42, 0.55);
  transform-style: preserve-3d;
}
.rd-door[data-size='sm'] .rd-door__frame { padding: 4% 4% 0; box-shadow: 0 2px 6px -2px rgba(15, 26, 42, 0.4); }

.rd-door__room {
  position: absolute;
  inset: 6% 6% 0;
  border-radius: 2px;
  background:
    radial-gradient(120% 70% at 50% 15%, var(--rd-room-light), color-mix(in srgb, var(--rd-room-light) 55%, transparent) 55%, var(--rd-room-far)),
    linear-gradient(180deg, var(--rd-room-light), var(--rd-room-far));
  overflow: hidden;
  display: grid;
  align-items: center;
  justify-items: end;
  padding: 0 6% 0 34%;
  opacity: 0;
  transition: opacity 500ms var(--vg-ease-out);
}
.rd-door[data-size='sm'] .rd-door__room { inset: 4% 4% 0; }

.rd-door__leaf {
  position: relative;
  width: 100%;
  transform-origin: left center;
  transform: rotateY(0deg);
  transition: transform 700ms cubic-bezier(0.16, 1, 0.3, 1), filter 700ms cubic-bezier(0.16, 1, 0.3, 1);
  will-change: transform;
}
.rd-door__svg { display: block; width: 100%; height: auto; }

.rd-door__numeral {
  font-family: var(--font-sans);
  font-weight: 800;
  font-size: 30px;
  letter-spacing: -0.02em;
  fill: var(--rd-brass-ink);
  font-variant-numeric: tabular-nums;
}
.rd-door__method {
  position: absolute;
  left: 50%;
  top: 38.5%;
  transform: translateX(-50%);
  max-width: 80%;
  padding: 2px 7px;
  border-radius: 3px;
  background: linear-gradient(135deg, var(--rd-brass-light), var(--rd-brass));
  color: var(--rd-brass-ink);
  font-size: 10px;
  font-weight: 750;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  box-shadow: inset 0 0 0 1px var(--rd-brass-dark);
}
.rd-door[data-size='md'] .rd-door__method { font-size: 8px; padding: 1px 5px; letter-spacing: 0.08em; }
.rd-door[data-size='sm'] .rd-door__method { display: none; }

/* ── states ───────────────────────────────────────────────────────────── */
.rd-door[data-state='open'] .rd-door__room,
.rd-door[data-state='opening'] .rd-door__room { opacity: 1; }
.rd-door[data-state='open'] .rd-door__leaf,
.rd-door[data-state='opening'] .rd-door__leaf {
  transform: rotateY(-68deg);
  filter: brightness(0.92);
}
.rd-door[data-state='opening'] .rd-door__leaf { transform: rotateY(-35deg); }

/* knocking: three short pulses on the latch side */
.rd-door[data-state='knocking'] .rd-door__leaf { animation: rd-knock 900ms cubic-bezier(0.16, 1, 0.3, 1) 1; }
@keyframes rd-knock {
  0%, 100% { transform: rotateY(0deg); }
  10%, 43%, 76% { transform: rotateY(-2.4deg); }
  25%, 58%, 91% { transform: rotateY(0deg); }
}

/* refused: the steel bolt slides across the latch (clip-path) */
.rd-door__bolt {
  position: absolute;
  left: 52%;
  right: -5%;
  top: 56.5%;
  height: 5.5%;
  border-radius: 3px;
  background: linear-gradient(180deg, var(--rd-steel-light), var(--rd-steel) 60%, var(--rd-steel-dark));
  box-shadow: 0 2px 6px -1px rgba(15, 26, 42, 0.55), inset 0 1px 0 rgba(255, 255, 255, 0.4);
  clip-path: inset(0 100% 0 0);
  transition: clip-path 420ms cubic-bezier(0.16, 1, 0.3, 1);
}
.rd-door[data-state='refused'] .rd-door__bolt { clip-path: inset(0 0 0 0); }

/* pending: an amber governance seal on the door */
.rd-door__seal {
  position: absolute;
  left: 50%;
  top: 70%;
  width: 22%;
  aspect-ratio: 1;
  transform: translate(-50%, -50%) scale(0.6);
  border-radius: 50%;
  padding: 4%;
  color: #fff;
  background: radial-gradient(circle at 35% 30%, color-mix(in srgb, var(--vg-hue-amber) 70%, white), var(--vg-hue-amber) 70%);
  box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.55), 0 6px 14px -4px rgba(15, 26, 42, 0.5);
  opacity: 0;
  transition: opacity 300ms var(--vg-ease-out), transform 300ms var(--vg-ease-out);
}
.rd-door[data-state='pending'] .rd-door__seal { opacity: 1; transform: translate(-50%, -50%) scale(1); }

@media (prefers-reduced-motion: reduce) {
  .rd-door__leaf { transition: filter 1ms; }
  .rd-door[data-state='open'] .rd-door__leaf,
  .rd-door[data-state='opening'] .rd-door__leaf { transform: none; opacity: 0.12; }
  .rd-door[data-state='knocking'] .rd-door__leaf { animation: none; outline: 2px solid var(--vg-focus); outline-offset: 3px; }
  .rd-door__bolt, .rd-door__seal, .rd-door__room { transition: none; }
}
</style>
