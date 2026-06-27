# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MilkStash is a SwiftUI + SwiftData iOS app for tracking a stash of frozen breast milk. Single app target, no package manager, no test target.

## Commands

Build (Simulator):
```bash
xcodebuild -scheme MilkStash -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run on a Simulator from the CLI (bundle id `Henok.MilkStash`):
```bash
xcrun simctl install booted "$(find ~/Library/Developer/Xcode/DerivedData/MilkStash-*/Build/Products/Debug-iphonesimulator -name MilkStash.app | head -1)"
xcrun simctl launch booted Henok.MilkStash
```

- **Haptics never fire in the Simulator** — `UIFeedbackGenerator` is a no-op there. Verify haptics on a physical device only.
- **Screenshot mode**: launch with the `-ScreenshotMode` argument. This swaps to an in-memory `ModelContainer` seeded by `ScreenshotData.populate` (`ScreenshotSupport.swift`) and shows `ScreenshotHost` instead of the live app.
- There is **no test suite and no linter** configured. Use `xcodebuild ... build` as the correctness gate.

## Architecture

### Domain vocabulary — important naming split
A **"Brick"** (user-facing term) is one physical Ziplock bag holding *N* individual milk bags. In code this is the **`MilkBag`** model, and many identifiers still say `ziplock` (`StashService.ziplockCount`, `FIFOItem.isWholeZiplock`, loop vars). The "Ziplock → Brick" rename was **user-facing strings only**; do not assume model/method names match the UI wording. When adding UI copy, say "Brick"; when reading code, "ziplock"/"MilkBag" mean the same container.

### Layering
- **Views** (`Views/*.swift`) — SwiftUI screens, presented from a custom tab container (see below). Sheets: `AddEditBagView` (add/edit a Brick), `UseMilkView` (log usage), `AlertsSheet`, `FilterSortSheet`.
- **ViewModels** (`ViewModels/ViewModels.swift`) — `@MainActor @Observable final class` types holding transient form/filter state (e.g. text-field strings, selection maps). They delegate all real logic to `StashService`.
- **`StashService`** (`Services/StashService.swift`) — pure static business logic, **no UI/SwiftData-context dependencies except where it writes**. FIFO planning, aggregates, expiration math, apply-use, discard, and history grouping all live here. Put new domain logic here, not in views.

### Data model (`Models/Models.swift`) — three `@Model` types
`MilkBag`, `AppSettings`, `UsageEvent` (registered in the `Schema` in `MilkStashApp.swift`).

- **Volumes are stored canonically in ounces.** `MilkBag.volumePerBagOz` is always oz; `displayUnit` (oz/mL) is only a presentation choice. Always convert through `UnitConversion` (`mLPerOz = 29.5735`); never compare a stored value against a raw user-entered number without converting.
- **`UsageEvent` stores its line items as a JSON blob** (`linesData` ⇄ `[UsageLineSnapshot]` via the `lines` computed property), by value — *not* as a SwiftData relationship. This is deliberate: history must survive deletion of the original `MilkBag`, and it avoids a second CloudKit-synced relationship. Events are treated as immutable.
- **CloudKit constraint**: the container is created with `cloudKitDatabase: .automatic` (falling back to `.none`, then in-memory). CloudKit requires every `@Model` stored property to be optional or have a default — preserve that pattern when adding fields, or sync init will fail.
- **`AppSettings` legacy unit migration**: older builds stored mL in `dailyOzGoal` / `lowStashThresholdOz`. Read these through `effectiveDailyOzGoal`, `effectiveLowStashThresholdOz`, and the `*DisplayValue` accessors — never the raw stored properties — and write via `setDailyGoalFromDisplayValue` / `setLowStashThresholdFromDisplayValue`. The heuristic in `LegacySettingsCompatibility` resolves legacy values at read time without rewriting persisted data.
- There is expected to be a **single `AppSettings` row**: `ContentView.task` seeds it if empty; views read it as `settings.first ?? AppSettings()`.

### FIFO logic (`StashService`)
"Use milk" pulls the oldest bricks first (sorted by `freezeDate`, then `expirationDate`). Individual milk bags must be thawed **whole**, so oz-based planning rounds up (`ceil`). Three entry points: `fifoRecommendation` (by oz), `fifoRecommendationByBags` (by bag count), and `manualPlan` (explicit per-brick selection). `applyUse` records the `UsageEvent` *before* decrementing `milkBagCount`, and flips a brick to `.used` when it hits zero.

### Navigation & design system (`Views/ContentView.swift`)
- **Not a `TabView`.** `ContentView` holds all five screens (Home / Inventory / Goal / History / Settings) in a `ZStack`, toggled by `opacity` on a `selectedTab` binding, with a custom `FFTabBar`.
- The tab bar **hides on scroll-down / reveals on scroll-up** via `TabBarVisibility` (an `ObservableObject` in the environment). A `ScrollView` opts in by calling `.tracksTabBar()`, which is a no-op below iOS 18 (`onScrollGeometryChange`).
- **Design tokens live in `ContentView.swift`**: `Color.ff*` (warm palette defined as light/dark-adaptive `UIColor` closures — e.g. `ffTerra` accent, `ffSage`, `ffButter`, `ffInk`/`ffInk2/3/4`, `ffBg`, `ffSurface`, `ffLine`), plus shared components `FFCard`, `FFEyebrow`, `FFDivider`, `FFEncouragement` and `Space`/`Radius` constants. Use these tokens rather than hardcoded colors/values so dark mode keeps working. Several `milk*` color names are legacy aliases.

### Haptics (`Haptics.swift`)
Central `Haptics` enum with `success()` / `warning()` / `light()`. The `UIFeedbackGenerator`s are `static let` (retained for the app's lifetime) because a throwaway generator gets deallocated before the Taptic Engine plays, silently dropping the haptic. Sheets call `Haptics.prepare()` in `.onAppear`.
- **Gotcha**: firing a notification haptic and then dismissing a sheet in the same runloop tick drops it. The pattern used here is to defer the dismiss (`AddEditBagView` and `UseMilkView` hold a brief confirmation overlay ~1s before `dismiss()`), which both confirms the action visually and lets the haptic play.

## Conventions
- `#Preview`s use `PreviewData.container()` for an in-memory seeded store.
- Targets iOS 17.6+; iOS-18-only APIs are gated behind `#available`. App version is `MARKETING_VERSION` in the pbxproj.
