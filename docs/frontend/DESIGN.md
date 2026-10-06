# DESIGN.md — Red Doors

The visual contract for the Red Doors UI. Red Doors follows the house
design system **Vault daylight glass** (user-level skill
`vault-ui-design`; canonical implementation: Arcanium,
`../arcanium/docs/frontend/config/DESIGN.md`). This document only records
what Red Doors adds. Where it is silent, the skill rules.

Values below are the ones in production in `ui/app/assets/css/main.css`
(the skill's `vault-glass.css` plus a Red Doors section) and
`ui/app/components/RedDoor.vue`.

## World

A daylight glass corridor: pale, window-lit ground with aluminium mullions,
frosted panes, black ink. Down that corridor stand **red doors**: the only
solid, saturated objects on the page. Everything else is glass; the doors are
lacquered wood and brass. That contrast is the brand.

Each page still has exactly one ink pane (the hero). Primary actions are ink,
blue is identity/links/approve, amber is governance, red is critical.

## The colour conflict, and the rule

In the house system red means **critical/denied** (`--vg-critical`). The
doors are red too. So:

- **Door red is a material, not a status.** The door tokens are used only
  inside `<RedDoor>`, never for text, borders or pills:

  | Token | Value | Use |
  | --- | --- | --- |
  | `--rd-lacquer-dark` / `--rd-lacquer` / `--rd-lacquer-light` | `#5f1414` / `#7f1d1d` / `#a3302e` | lacquer gradient across the leaf |
  | `--rd-lacquer-sheen` | `rgba(255,236,228,.22)` | top-light sheen |
  | `--rd-edge` | `#4a0f0f` | leaf edge, panel recesses |
  | `--rd-brass-dark` / `--rd-brass` / `--rd-brass-light` | `#8a6a3a` / `#b08d57` / `#dcc28f` | plate, lever, method label |
  | `--rd-brass-ink` | `#2a1d0a` | numerals and labels on brass: 5.3:1 on `--rd-brass`, 9.5:1 on `--rd-brass-light` |
  | `--rd-steel-dark` / `--rd-steel` / `--rd-steel-light` | `#3e4855` / `#5b6878` / `#a9b4c2` | the refusal bolt |
  | `--rd-room-light` / `--rd-room-far` | `#fff8e7` / `#dfe6ee` | the lit room behind an open door |
  | `--rd-doorway` | `#1b2433` | the reveal around the leaf |

- **Refusal is never shown by colour alone.** A refused door stays shut, a
  steel bolt slides across the latch, the accessible label says "refused by
  Vault — bolted", and the decision panel shows Vault's own error in
  `--vg-critical` on its tint.
- **Pending** (door 8) is an amber governance seal (from `--vg-hue-amber`) on
  the door, plus the words "Waiting for a second person".
- **Opened** is the door swung on its hinge with the room lit, plus "Opened
  by Vault".

## `<RedDoor>`

Props: `number`, `method` (engraved on brass), `title`, `state`
(`closed · knocking · opening · open · refused · pending`), `size`
(`lg` corridor, clamp 180–260 px · `md` grid card, 132 px · `sm` header
icon, 44 px). The `room` slot holds what appears behind an open door (the
business item and the released value). `role="img"` with an `aria-label`
that states door, method and state in words.

### The one motion moment

The swing: `rotateY(-68deg)` on the hinge edge, **700 ms,
`cubic-bezier(0.16, 1, 0.3, 1)`**, revealing the lit room. Supporting
micro-motion only: knocking = three short pulses on the latch side (900 ms,
once); the bolt slides in by `clip-path` (420 ms); the seal scales in
(300 ms). The swung leaf projects below the frame in perspective, so the
component reserves `0.14 × width` underneath.

With `prefers-reduced-motion: reduce` nothing swings or pulses: an open door
fades its leaf (the room shows through), knocking becomes a focus outline.

## Page primitives specific to Red Doors

- **Corridor**: the eight doors in story order as a receding row (CSS
  perspective and scale, not an image); the active door is in focus.
- **"Behind the door" room**: the business item title, the released value
  (mono only for the value itself), and its lifetime countdown when Vault
  returned a TTL.
- **"How Vault decided"**: numbered steps, all from real data: identity →
  auth method → role → policies (policy text verbatim, mono) → token TTL →
  outcome. Missing data reads "not reported".
- **Audit drawer**: the joined Vault audit records, raw JSON collapsible,
  HMAC'd fields marked "HMAC — Vault never logs the value".
- **Triggered by / Opened by**: two distinct chips everywhere (the person who
  pressed the button vs the identity Vault evaluated).

## Accessibility

Inherits the skill's rules (AA contrast verified, including status text on
its own tint; no opacity-faded meaning; visible focus; `lang` on `<html>`).
Gate: axe WCAG 2.1 A/AA, 0 violations at 1440×900 and 390×844 on every
screen; reduced-motion screenshots in the Playwright set.

## Component sheet

`/_design` shows every door state and size, the swing, and the signal pills
beside the doors. It is exposed only with `NUXT_PUBLIC_DESIGN_SHEET=true`.
