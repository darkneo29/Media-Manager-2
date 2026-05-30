# UI Component Library

A reusable component library for Media Manager with tech-focused styling featuring violet (#6B5CE7) and cyan (#00D9FF) accent colors.

## Components

### MediaCard

A reusable card component for displaying media items with poster images, titles, and status badges.

**Features:**
- Poster image with 2:3 aspect ratio
- Title overlay with gradient background
- Optional subtitle
- Optional status badge
- Rounded corners with gradient border
- Subtle shadow with violet glow
- Tap interaction with scale animation

**Usage:**
```swift
MediaCard(
    imageURL: movie.posterUrl,
    title: movie.title,
    subtitle: String(movie.year),
    badge: movie.monitored ? .monitored : .unmonitored,
    onTap: {
        // Handle tap
    }
)
```

**Badge Types:**
- `.monitored` - Violet badge with eye icon
- `.unmonitored` - Gray badge with eye slash icon
- `.downloading` - Cyan badge with download icon
- `.available` - Green badge with checkmark icon
- `.missing` - Amber badge with exclamation icon

---

### GlowingButton

A stylized button with glow effects and three variants.

**Features:**
- Primary, secondary, and destructive variants
- Optional icon support
- Glow effect that intensifies on press
- Scale animation on interaction
- Full-width by default

**Usage:**
```swift
// Primary button (filled with violet)
GlowingButton("Add Movie", icon: "plus.circle.fill", variant: .primary) {
    // Handle action
}

// Secondary button (outlined)
GlowingButton("Cancel", variant: .secondary) {
    // Handle action
}

// Destructive button (red)
GlowingButton("Delete", icon: "trash.fill", variant: .destructive) {
    // Handle action
}
```

---

### StatusBadge

A pill-shaped status indicator with icon and text.

**Features:**
- Five predefined status types with appropriate colors
- Icon + text layout
- Subtle glow for active states (monitored, downloading, available)
- Compact capsule design

**Usage:**
```swift
StatusBadge(type: .monitored)
StatusBadge(type: .downloading)
StatusBadge(type: .available)
StatusBadge(type: .missing)
StatusBadge(type: .unmonitored)
```

---

### SectionHeader

Styled section headers with optional subtitle and trailing action button.

**Features:**
- Bold title with optional subtitle
- Optional trailing action button
- Gradient underline accent (violet to cyan)
- Horizontal padding built-in

**Usage:**
```swift
// Simple header
SectionHeader("Movies", subtitle: "124 items")

// With action button
SectionHeader(
    "Recently Added",
    subtitle: "Last 7 days",
    action: SectionHeader.ActionConfig(
        title: "View All",
        icon: "arrow.right",
        handler: { /* Handle action */ }
    )
)
```

---

### PlaceholderView

Reusable empty state and placeholder view with icon, message, and optional action.

**Features:**
- Large icon with gradient circular background
- Title and description text
- Optional action button
- Centered full-screen layout
- Perfect for empty states, coming soon features, and no results

**Usage:**
```swift
// Empty state with action
PlaceholderView(
    icon: "film.stack",
    title: "No Movies Yet",
    description: "Start building your collection by adding your first movie",
    action: PlaceholderView.ActionConfig(
        title: "Add Movie",
        icon: "plus.circle.fill",
        handler: { /* Handle action */ }
    )
)

// Coming soon state
PlaceholderView(
    icon: "sparkles",
    title: "Coming Soon",
    description: "This feature is currently under development"
)
```

---

### LoadingOverlay

A loading indicator overlay with gradient spinner and optional message.

**Features:**
- Semi-transparent dark background
- Gradient spinner with continuous rotation
- Optional loading message
- Fade-in animation on appear
- View modifier for easy integration

**Usage:**
```swift
// As a view
LoadingOverlay(message: "Loading movies...")

// As a modifier
ContentView()
    .loadingOverlay(isShowing: isLoading, message: "Fetching data...")
```

---

## Design Tokens

### Colors
- **Primary:** Violet `#6B5CE7`
- **Secondary:** Cyan `#00D9FF`
- **Background Dark:** `#0f0f1e`, `#1a1a2e`, `#16213e`
- **Destructive:** Red `#EF4444`
- **Success:** Green `#10B981`
- **Warning:** Amber `#F59E0B`
- **Gray:** `#6B7280`

### Typography
- **Large Title:** 24pt, Bold
- **Header:** 22pt, Bold
- **Body:** 16pt, Semibold
- **Subhead:** 14-15pt, Semibold/Medium
- **Caption:** 12pt, Semibold/Medium

### Effects
- **Border Radius:** 12pt (standard), capsule (badges/buttons)
- **Shadow:** Violet glow with 0.2-0.3 opacity
- **Animation:** easeInOut 0.15s for interactions
- **Border:** 1-2pt with gradient or solid color

---

## Examples

### Movie Grid
```swift
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
    ForEach(movies) { movie in
        MediaCard(
            imageURL: movie.posterUrl,
            title: movie.title,
            subtitle: String(movie.year),
            badge: movie.monitored ? .monitored : .unmonitored,
            onTap: { selectedMovie = movie }
        )
    }
}
.padding()
```

### Empty State
```swift
if movies.isEmpty {
    PlaceholderView(
        icon: "film.stack",
        title: "No Movies Yet",
        description: "Start building your collection",
        action: PlaceholderView.ActionConfig(
            title: "Add Movie",
            icon: "plus.circle.fill",
            handler: { showAddMovie = true }
        )
    )
}
```

### Form Actions
```swift
VStack(spacing: 16) {
    GlowingButton("Save Changes", icon: "checkmark.circle.fill") {
        save()
    }

    GlowingButton("Cancel", variant: .secondary) {
        dismiss()
    }

    GlowingButton("Delete", icon: "trash.fill", variant: .destructive) {
        delete()
    }
}
.padding()
```

---

## Notes

- All components use dark mode styling optimized for OLED displays
- Components are fully composable and can be nested
- SwiftUI previews included for all components
- Color extension with hex support is included in MediaCard.swift
- Components follow iOS design guidelines while maintaining custom branding
