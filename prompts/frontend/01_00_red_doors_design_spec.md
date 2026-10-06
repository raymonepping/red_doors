# Frontend 01_00 — Red Doors design spec

## Context

Every Vault project uses the **Vault daylight glass** system. Before
anything else, load the user-level skill **`vault-ui-design`**
(`~/.claude/skills/vault-ui-design/`: `SKILL.md`, `vault-glass.css`,
`shell.css`) and read the canonical implementation
(`../arcanium/arcanium/ui/`, `../arcanium/docs/frontend/config/DESIGN.md`).
This spec only adds what is specific to Red Doors; where it is silent, the
skill rules.

Output of this prompt: `docs/frontend/DESIGN.md` for Red Doors (structure
copied from Arcanium's), plus the token additions below in the UI's
`main.css`. No screens yet (that is `01_01`).

## The world

Daylight glass corridor: pale window-lit ground with aluminium mullions,
frosted panes, black ink. Down that corridor stand **red doors** — the only
saturated, solid objects on the page. Everything else is glass; the doors
are lacquered wood and brass. That contrast *is* the brand.

## The colour conflict (and its resolution)

In `vault-glass.css`, red already means **critical/denied**
(`--vg-critical #b01818`). The doors are red too. Rule:

- **Door red is a material, not a status.** Add `--rd-door-lacquer`
  (oxblood, e.g. `#7f1d1d` → `#9b2c2c` gradient with a soft specular
  highlight), `--rd-door-edge`, `--rd-brass` (`#b08d57`, handle and number
  plate), `--rd-brass-ink` for numerals on brass. They are used **only**
  inside the door illustration — never for text, borders or pills.
- **Denial is never shown by colour alone.** A refused door stays shut,
  a steel bolt slides across it, the label reads "Refused by Vault" with a
  lock-bar icon, and the panel below uses `--vg-critical` text on its tint.
  Opened = door ajar + the room behind it lit; refused = bolt + label;
  pending (door 8) = amber governance seal on the door + "Waiting for a
  second person".
- Contrast: every text token stays AA (verify with axe); numerals on brass
  ≥ 4.5:1.

## The door (authored SVG component `RedDoor.vue`)

- A panel door in near-elevation: frame, two recessed panels, brass lever
  handle, brass number plate with the door number, a small engraved method
  label under it ("KUBERNETES", "OIDC", …) in `--rd-brass-ink`.
- States: `closed`, `knocking`, `opening`, `open`, `refused`, `pending`.
- **One authored motion moment**: the swing. `perspective` + `rotateY`
  around the hinge edge, ~700ms, `cubic-bezier(0.16,1,0.3,1)`, revealing a
  glass room behind. Knocking = three short handle-side pulses
  (transform only). Refused = the bolt slides in (clip-path). With
  `prefers-reduced-motion`, states cross-fade instead.
- Must read at three sizes: corridor (large, perspective row), grid card
  (medium), detail header (small icon).

## Layout primitives specific to Red Doors

- **Corridor**: the eight doors in story order as a receding row — use CSS
  perspective/scale for depth, not an image. The corridor floor and walls
  are glass panes; the active door is in focus, others slightly smaller.
- **"Behind the door" room**: a glass pane that opens with the door,
  showing the business item title, the real released value (mono only for
  the value itself), and its lifetime (countdown when there is a TTL).
- **Decision panel** ("How Vault decided"): identity → auth method → role →
  policies (policy text in a mono block) → token TTL → outcome. Vertical,
  numbered steps, each from real data; missing data shows "not reported".
- **Audit drawer**: the joined audit entries, raw JSON collapsible, HMAC'd
  fields visibly marked "HMAC — Vault never logs the value".
- **Triggered by / opened by** shown as two distinct chips everywhere.

## Pages (designed here, built in 01_01)

Corridor (guided, the hero is the ink pane: "Eight doors. Eight ways in."),
All doors (grid), Door detail, Approvals (door 8 inbox), Audit, Cluster
(Vault nodes, Raft, seal chain, VSO), Sign-in. Sidebar groups: *Corridor* ·
*Doors 1–8* · *Governance (Approvals, Audit)* · *Platform (Cluster)*.

## Deliverables

- `docs/frontend/DESIGN.md` (Red Doors), stating it follows
  `vault-ui-design` and documenting the door material tokens, door states,
  the colour-conflict rule and the motion moment.
- Token additions in `ui/app/assets/css/main.css` (based on
  `vault-glass.css`).
- A static component sheet page (`/_design`, dev-only) showing `RedDoor`
  in every state and size, for sign-off before screens are built.

## Validation

Screenshot `/_design` at 1440×900 and 390×844; axe scan 0 violations;
reduced-motion screenshot shows no swing. Present the sheet to the user for
sign-off before 01_01.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
