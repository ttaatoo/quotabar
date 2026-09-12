---
name: QuotaBar
description: Dark menu-bar quota utility; Settings is a compact night preference pane.
colors:
  popover-bg: "#1B1B1C"
  popover-elevated: "#2A2A2D"
  settings-page: "#1A191F"
  settings-sidebar: "#16151C"
  settings-group: "#24222C"
  settings-field: "#12111A"
  settings-primary: "#F4F1F8"
  settings-secondary: "#A8A3B5"
  settings-tertiary: "#7A7488"
  settings-hairline: "#B4AACC2E"
  settings-accent: "#B56BFF"
  settings-accent-soft: "#D6B8FF"
  settings-danger: "#F26661"
  settings-warning: "#FF7A1A"
  provider-cursor: "#5C8CFF"
  provider-chatgpt: "#B56BFF"
  provider-glm: "#3DDB96"
  provider-grok: "#F29E38"
  provider-opencode: "#38C7D1"
typography:
  title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.25
  sidebar:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 500
    lineHeight: 1.2
  row:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  caption:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.35
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.4
rounded:
  sm: "7px"
  md: "10px"
  well: "7px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "22px"
  sidebar: "172px"
  window-width: "680px"
  window-height: "560px"
components:
  button-primary:
    backgroundColor: "{colors.settings-accent}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "28px"
  button-primary-hover:
    backgroundColor: "{colors.settings-accent}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.sm}"
    height: "28px"
  button-secondary:
    backgroundColor: "{colors.settings-field}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.sm}"
    padding: "0 10px"
    height: "26px"
  secret-field:
    backgroundColor: "{colors.settings-field}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.sm}"
    height: "30px"
  nav-item-selected:
    backgroundColor: "{colors.settings-accent}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.sm}"
    height: "28px"
  settings-group:
    backgroundColor: "{colors.settings-group}"
    textColor: "{colors.settings-primary}"
    rounded: "{rounded.md}"
    padding: "4px 0"
---

# Design System: QuotaBar

## 1. Overview

**Creative North Star: "Night Menu Extra"**

QuotaBar is a menu-bar utility, not a settings product. The shipped popover is a 320×360 dark pill of meters; Settings must feel like that chrome opened one notch wider. A power user glances at credentials from a floating preference window on a Mac at night. Surfaces are purple-tinted dark neutrals. One violet accent does the work of selection, focus, and primary actions (≤10% of the pane).

The system rejects bright System Settings clones, stacked identical provider cards, rainbow section headers, glass, and motion that is not a state change. Density is a feature. Familiarity with Raycast Preferences, Linear Settings, and compact Cursor/macOS preference windows is the bar.

**Key Characteristics:**
- Restrained: tinted dark neutrals + one purple accent
- Sidebar + one pane (never an endless card wall)
- SF Pro only; SF Mono for pasted JSON
- Tonal elevation (lighter = higher), no drop shadows
- Provider hues stay on 12pt icons, never on full-width fills

## 2. Colors

Restrained night neutrals, chroma leaned toward the violet accent so the pane does not read as dead gray.

### Primary
- **Violet Signal** (`{colors.settings-accent}`): Add account, selected nav row, focus ring, toggle on. Same hue as `Theme.logoPurple`. Rarity is the point.

### Neutral
- **Night Page** (`{colors.settings-page}`): Settings content canvas.
- **Night Rail** (`{colors.settings-sidebar}`): Sidebar, one step darker than the page.
- **Desk Group** (`{colors.settings-group}`): Grouped preference rows (the only “card”).
- **Ink Field** (`{colors.settings-field}`): Secret fields and JSON editor.
- **Paper** (`{colors.settings-primary}`): Primary labels. Not `#fff`.
- **Mist** (`{colors.settings-secondary}`): Hints, subtitles, idle nav.
- **Dusk** (`{colors.settings-tertiary}`): Group labels, “Off” badges, version.
- **Violet Hairline** (`{colors.settings-hairline}`): 1px group and field strokes.

### Named hues (icons only)
Cursor blue, ChatGPT violet, GLM green, Grok amber, OpenCode teal tint the bundled 12pt brand marks and the popover meters. They are not section backgrounds and not primary button fills.

### Semantic
- **Warning** (`{colors.settings-warning}`): Rejected Grok token.
- **Danger** (`{colors.settings-danger}`): Delete affordance.

**The One Voice Rule.** Purple accent occupies ≤10% of Settings: primary actions, current sidebar row, focus, and toggle-on. Provider rainbow on large fills is forbidden.

**The Tinted Night Rule.** Settings neutrals lean violet. Do not use `#000`, `#fff`, or untinted gray. Do not restyle the popover meters to chase Settings tokens; popover keeps `Theme.background` / `Theme.elevated`.

## 3. Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Mono for JSON only

**Character:** Native macOS product type. Tight 1.2-ish scale. No display face.

### Hierarchy
- **Title** (semibold, 16): Pane name only.
- **Sidebar** (medium / semibold when selected, 12.5): Nav labels.
- **Row** (medium, 13): Preference titles, account emails.
- **Body** (regular, 12): Pane subtitles.
- **Caption** (regular, 11): Field hints, About disclaimer.
- **Mono** (regular, 11): Advanced JSON.

**The One Family Rule.** SF Pro for every Settings label. No Inter, no rounded display, no all-caps section shouting. Group labels are 10.5 medium dusk, title case.

## 4. Elevation

No shadows. Depth is a three-step night stack: rail darker than page, group lighter than page. Hairline at 1px. Selected nav is a full-row violet wash, never a side stripe.

**The Flat Night Rule.** If you can see a drop shadow, remove it. If a group is nested inside a group, flatten it.

## 5. Components

### Buttons
- **Shape:** Continuous rounded rect (7)
- **Primary:** Violet fill, paper label, 28pt min height; hover full opacity, press slightly darker, disabled 40%
- **Secondary:** Ink field fill + hairline; used for “Add account” once a list exists
- **Icon:** 28×28 field fill, dusk icon; trash uses danger; help string required

### Secret fields
- Ink fill, hairline, 30pt height, 12.5 body
- Reveal eye is a 22pt hit inside the field
- Focus: 1.5pt violet ring (system focus effect is disabled here)
- Warning: amber ring + caption when a Grok value is rejected
- Visible label above the field; placeholder is not the only name

### Sidebar
- 172pt rail, 28pt rows, 7pt selected wash
- Brand marks 12pt for provider rows; SF Symbols only for Quota / App chrome; selected icon and label use accent / paper
- “Off” badge when that provider is hidden from the popover
- Arrow keys move the section

### Groups / rows
- One grouped surface per cluster (10pt radius)
- Rows 36pt min, 12pt horizontal padding
- Dividers are inset hairlines, not stacked cards
- Advanced disclosure starts collapsed

### Empty states
- Soft well + brand mark (or SF Symbol for non-provider empty states), title, one teaching sentence, one primary action
- Never a lone “No accounts yet.”

### Popover account cards
- Tight header: brand mark, email, plan badge, active check
- Each quota window is two rows: title + percent + reset chip, then the bar. Do not bury reset under a third caption
- Credits and optional plan expiry share one footer row. Omit expiry when the API does not publish it
- Purple selection ring and tint stay. No nested cards, no side stripe

### Navigation
- Three quiet groups: Quota, Accounts, App
- First open maps to the popover’s selected provider; later visits keep the user’s pane

## 6. Do's and Don'ts

### Do:
- **Do** keep Settings in the Night Menu Extra register: dark, dense, native.
- **Do** put every Settings color through `Theme` tokens.
- **Do** collapse Advanced cookie/JSON by default.
- **Do** teach empty ChatGPT, Grok, and OpenCode lists with a next action.
- **Do** leave existing Keychain account names and `config.json` keys unchanged; new Grok account keys are additive.

### Don't:
- **Don't** clone bright macOS System Settings (large white grouped lists, toolbar icon grid).
- **Don't** stack identical icon-title-hint cards down an endless window.
- **Don't** use border-left / side-stripe accents on rows or groups.
- **Don't** fill primary buttons with teal, green, amber, or blue; violet is the only action fill.
- **Don't** nest cards, add glass blur, gradient text, or decorative motion.
- **Don't** restyle popover meter geometry or rewrite `NSPopover.contentSize`.
