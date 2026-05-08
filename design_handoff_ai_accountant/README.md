# Handoff: AI Accountant Mobile App

## Overview
This is a mobile-first wireframe design for an AI-powered accounting app that lets users capture invoices/receipts via camera, review AI-extracted data in a queue, and manage their transaction history and reports. The design covers 5 core screens with multiple layout variations explored.

## About the Design Files
The HTML file in this bundle (`AI Accountant Wireframes.html`) is a **design reference prototype** — a low-fidelity wireframe showing structure, flow, and interactions. It's not production code to copy directly. Your task is to **recreate these wireframes in your target codebase** (React Native, Flutter, Swift, Kotlin, or whatever framework you're using) following your existing patterns and component libraries. If no codebase exists yet, choose the most appropriate mobile framework for the project and implement the designs there.

## Fidelity
**Low-fidelity (lofi) wireframes.** These are sketchy, paper-like mockups showing:
- Layout structure and information hierarchy
- Component placement and sizing
- User flows and interactions
- Multiple variations to compare

**You should:**
- Use these as a guide for layout and functionality
- Apply your existing design system for final styling (colors, typography, spacing, shadows)
- Focus on getting the structure and interactions right; visual polish comes from your brand guidelines

## Preferred Variants
After exploring multiple directions, the following were selected as preferred:
- **Queue / Home**: Variant **C** (grouped + bulk bar) — date-grouped rows with a sticky bulk-confirm bar
- **Camera flow**: Variant **B** (clean camera, no context pills) — Sale/Purchase decided before or after, not during capture
- **Badge / counter**: **Red dot** notification style on thumbnail
- **Report**: Slash-headings list with bottom-up sheet overlay

## Screens / Views

### 1. Queue / Home (Variant C — Preferred)
**Purpose:** Default landing screen. Shows AI-captured transactions awaiting user review and confirmation.

**Layout:**
- **Top bar** (fixed): Two tabs: "Sale" | "Purchase" — switch between transaction types
- **Content area** (scrollable):
  - Date section headers ("Today", "Yesterday") — Caveat font, 18px, 2px margin
  - Table rows under each date, grid layout: `#` | `Party` | `Amount` | `Time` | `Checkbox`
  - Party name is **clickable** (underlined, blue, bold)
- **Bulk action bar** (sticky above nav): Shows count of selected items + "Confirm" button (accent color)
- **Bottom nav** (fixed): 5 icons — Queue (active) | History | Camera (center, larger) | Report | Profile

**Interactions:**
- **Tap party name** → Opens full-screen overlay with Excel-like sheet (challan data)
  - Sheet slides up from bottom
  - Header shows filename: `challan_<party_name>.xlsx` with green dot
  - "Done" button in header
  - Toolbar with File/Edit/View/Σ/% buttons
  - Spreadsheet grid: columns A-F, rows 1-8+
  - Footer shows row count + sum
- **Tap "Done" in sheet** → Sheet closes, shows toast:
  1. Processing toast: "Your sale challan for <party> is being processed…" (2s)
  2. Success toast: "<party> · sale challan is done" (2.6s, green background, checkmark icon)
  3. Row greys out (opacity: .55), checkbox turns green with checkmark
- **Checkbox tap** → Toggle selection, update bulk bar count
- **Bulk "Confirm" button** → Process all checked items (not implemented in wireframe)

**Components:**
- **Table row**: 
  - Grid: `24px | 1fr | 60px | 60px | 24px`
  - Border: 1.5px solid, dashed between rows
  - Padding: 6px 8px
  - `.party` has underline, cursor pointer, color blue
  - `.trow.done`: greyed out, party has strikethrough
  - `.trow.processing`: opacity .55
- **Toast**:
  - Position: absolute, bottom 64px (above nav)
  - Border-radius: 8px, padding: 7px 10px
  - Background: dark (processing) or green (success)
  - Spinner (12px) or checkmark icon on left
  - Slide-up animation (.25s)
- **Sheet overlay**:
  - Full-screen, background: rgba(20,30,60,.35)
  - Sheet: white, border-radius 12px 12px 0 0
  - Slide-up animation: translateY(100%) → translateY(0), .35s cubic-bezier

**State:**
- Current tab: "Sale" or "Purchase"
- Rows: array of `{ party, amount, time, checked, status: 'pending'|'processing'|'done' }`
- Active overlay: null or party name
- Toast queue: array of toast messages

### 2. Camera Flow (Variant B — Preferred)
**Purpose:** Capture receipt/invoice photos. No Sale/Purchase context shown during capture.

**Layout:**
- **Viewfinder** (full-screen): Dark background (simulated camera view)
  - 4 corner brackets (22×22px, 2.5px borders, white)
  - Hint text centered: "point at receipt"
- **Bottom strip**:
  - Left: Thumbnail (38×38px) with red badge showing count (top-right, 18px circle, accent color)
  - Center: Shutter button (56×56px circle, white fill, dark ring inside)
  - Right: Plus button (38×38px, dashed circle, "+" text)
- **Bottom nav** (same as Queue)

**Interactions:**
- **Tap shutter** → Capture image, increment badge count
- **Tap thumbnail** → Show captured images (not detailed in wireframe)
- **Tap plus** → Add more images or start new batch

**State:**
- Capture count: number
- Images: array of image blobs/URIs

### 3. History
**Purpose:** Show confirmed transactions, grouped by month.

**Layout:**
- **Top bar**: Two tabs: "All" | "Sale" (can extend to Purchase filter)
- **Content**:
  - Month header: "May 2026", "April 2026" — Caveat font, 18px
  - Card list under each month
- **Card**:
  - Grid: `28px icon | 1fr details | auto amount`
  - Icon: 26×26px square, border, centered "S" or "P"
  - Details: Party name (bold, 12px) + date + type (11px, grey)
  - Amount: green (+) for sale, red (−) for purchase
  - Border: 1.5px solid, border-radius 8px, padding 8-10px

**Interactions:**
- **Tap card** → Navigate to transaction detail (not shown in wireframe)
- **Swipe** → Potential edit/delete actions (not shown)

### 4. Report (Preferred — Slash Headings)
**Purpose:** Show business insights via categorized reports.

**Layout:**
- **Top bar**: Two tabs: "Insights" | "Export"
- **Content**: Vertical list of report categories
  - Each item: heading + description + emoji
  - Heading: `/act_now`, `/hero_sku_health`, etc. — monospace, 12px, bold
  - Description: 11px, grey, line-height 1.35, emoji on left (🚨, 🏆, 💀, etc.)
  - Border-bottom: 1px dashed, padding 9px 4px
- **Bottom nav** (Report active)

**Interactions:**
- **Tap a report heading** → Show loading spinner (append to heading), then:
  - Full-screen overlay with sheet (same component as Queue challan)
  - Sheet slides up from bottom
  - Header: filename `/<category>.csv` with green dot, ✕ close button (top-right)
  - Spreadsheet grid with report data (stock_item, sales, purchases, etc.)
  - Footer: row count + sum
- **Tap ✕** → Sheet slides down, overlay fades out

**Report Categories:**
1. `/act_now` — Items at risk of lost sales
2. `/hero_sku_health` — Top-performing revenue drivers
3. `/dead_capital` — Capital locked with zero returns
4. `/buying_mistakes` — Purchases without sales justification
5. `/wind_down` — Items clearing out
6. `/risk_watch` — Needs monitoring
7. `/full_portfolio_health` — Complete sorted view

**State:**
- Active report: null or category name
- Loading: boolean per category
- Report data: fetched rows for active category

### 5. Profile
**Purpose:** User settings and account management.

**Layout:**
- **Header card**:
  - Avatar (44×44px circle, initials), name, email + GST
  - Border, border-radius 8px, padding 10px
- **Settings list**:
  - Each row: label | arrow (›)
  - Border: 1.5px dashed, border-radius 6px, padding 8px 10px
  - Gap: 4px between rows
- Options: Business details, Tax/GST, Currency & date, Backup & export, AI accuracy, Help & support, Sign out (red)

**Interactions:**
- **Tap row** → Navigate to detail screen (not shown)

## Bottom Navigation (All Screens)
- **5 tabs**: Queue | History | Camera | Report | Profile
- **Camera** is center, elevated (larger circle, 36×36px)
- Border-top: 1.5px solid
- Active tab: bold text, top bar (2.5px)
- Spacing: grid, equal columns

## Interactions & Behavior

### Challan Sheet Flow
1. User taps party name in Queue
2. Overlay fades in (rgba background)
3. Sheet slides up from bottom (.35s cubic-bezier)
4. User reviews/edits spreadsheet data
5. User taps "Done"
6. Sheet slides down, overlay fades out
7. Processing toast appears (spinner + text)
8. After 2s, processing toast fades out
9. Success toast appears (checkmark + text)
10. Row greys out, checkbox turns green
11. After 2.6s, success toast fades out

### Report Sheet Flow
1. User taps report heading
2. Loading spinner appears on that row
3. After ~900ms, spinner disappears
4. Sheet slides up with report data
5. User scrolls/reviews data
6. User taps ✕ button
7. Sheet slides down, overlay fades out

### Toast System
- **Position**: Absolute, bottom 64px (above nav), left/right 8px
- **Stack**: Multiple toasts stack vertically (gap 6px)
- **Auto-dismiss**: Success toasts auto-dismiss after duration; processing toasts stay until dismissed by code
- **Animation**: Slide-up + fade-in on show, reverse on hide

## Design Tokens

### Colors
- `--paper`: #f6f1e6 (background)
- `--ink`: #16181d (text, borders)
- `--ink-soft`: #3a3f49 (secondary text)
- `--pen`: #1f3a8a (links, clickable items)
- `--accent`: #d94f3a (buttons, badges, warnings)
- `--accent-2`: #f2c94c (highlights)
- `--muted`: #8a8576 (tertiary text)
- `--line`: #b9c8df (subtle borders)

Success green: #1d7a3a
Sheet background: #fdfaf1
Grid header: #e9eef5

### Typography
- **Headings**: Caveat, 700 weight
- **Body**: Kalam, 400/700 weight
- **Captions**: Architects Daughter, 400 weight
- **Monospace**: JetBrains Mono, 400/600 weight

Sizes:
- H1: 64px
- Section heading: 36px
- Screen title: 22px
- Body: 12-14px
- Caption: 11px
- Tiny: 9-10px

### Spacing
- Phone screen: 300×600px (design canvas)
- Top bar height: ~38px
- Bottom nav height: ~52px
- Content padding: 10-12px
- Row padding: 6-8px
- Card padding: 8-10px
- Gap between cards: 4-6px

### Borders & Radii
- Border width: 1.5-2.5px
- Phone border-radius: 36px
- Screen border-radius: 22px
- Card border-radius: 6-8px
- Button border-radius: 4-14px (pill)
- Sheet top radius: 12px

### Shadows
- Phone: 4px 6px 0 rgba(20,30,60,.08)
- Toast: 2px 3px 0 rgba(0,0,0,.15)

## State Management

### Queue Screen
```
state = {
  activeTab: 'Sale' | 'Purchase',
  rows: [
    { id, party, amount, date, time, checked, status: 'pending'|'processing'|'done' }
  ],
  selectedCount: number,
  activeSheet: null | { party, data },
  toasts: []
}
```

### Camera Screen
```
state = {
  captureCount: number,
  images: []
}
```

### Report Screen
```
state = {
  activeReport: null | categoryName,
  loadingCategory: null | categoryName,
  reportData: { [category]: rows[] }
}
```

## Assets
- **Icons**: Simple line-art or emoji placeholders used in wireframe
  - ≡ (Queue), ⟲ (History), ◉ (Camera), ▤ (Report), ☺ (Profile)
  - Replace with your icon library
- **Fonts**: Google Fonts (Caveat, Kalam, Architects Daughter, JetBrains Mono)
  - Use your app's existing font stack
- **Challan Excel data**: Sample data shown in sheet; replace with real API data

## Files
- `AI Accountant Wireframes.html` — The full interactive wireframe prototype. Open in a browser to explore all screens and interactions.

## Implementation Notes
1. **Framework choice**: This design works best in React Native, Flutter, or native (Swift/Kotlin). Choose based on your team's expertise.
2. **Sheet component**: The challan/report sheet is reusable — build one generic bottom-sheet component.
3. **Toast system**: Use a toast/snackbar library or build a simple queue-based system.
4. **Navigation**: 5-tab bottom nav with stack navigators per tab.
5. **Camera**: Use device camera API (not shown in wireframe UX for permissions, etc.)
6. **Data source**: Queue/history/report data comes from backend API; wireframe uses fixtures.
7. **Offline**: Consider offline-first architecture — capture photos locally, sync when online.
8. **Accessibility**: Add labels, touch targets (min 44pt), screen reader support.

## Next Steps
1. Review the HTML wireframe in a browser
2. Map wireframe components to your codebase's component library
3. Set up navigation structure (tab navigator + stacks)
4. Build bottom sheet component first (reused in Queue and Report)
5. Implement Queue screen with clickable party → sheet → toast flow
6. Implement Camera screen with capture + badge counter
7. Implement Report screen with slash-list → sheet
8. Implement History and Profile screens
9. Connect to backend API for real data
10. Add error states, empty states, loading skeletons

---

**Questions?** If anything is unclear, open the HTML file and interact with the prototype — it's fully clickable and shows all the flows described above.
