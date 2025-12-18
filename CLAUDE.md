# Claude Code Guidelines for VibeRSS

## Development Guidelines

### Research First
- Always research Apple's Human Interface Guidelines (HIG) before implementing UI features
- Look up best practices for SwiftUI performance and animations
- Search for the recommended approach before writing custom implementations

### Use Native APIs
- Prefer native iOS APIs over custom gesture/animation implementations
- For scrolling/paging: Use `ScrollView` with `.scrollTargetBehavior(.paging)` and `.scrollTargetLayout()`
- For horizontal paging: Use `TabView` with `.tabViewStyle(.page())`
- For smooth animations: Use SwiftUI's built-in `withAnimation` and spring animations

### Liquid Glass UI (iOS 26+)
- Wrap multiple glass effects in `GlassEffectContainer` for optimized rendering and morphing
- Apply `.glassEffect()` last in the modifier chain
- Use `.glassEffect(.regular.interactive())` for interactive elements
- Glass UI should be reserved for navigation/control layers, not main content

### Performance
- Use `LazyVStack`/`LazyHStack` for scrollable content
- Use `.containerRelativeFrame()` for full-screen paging cards
- Avoid custom `CADisplayLink` animations when SwiftUI native options exist
- Test on device for 120fps ProMotion smoothness

### Code Style
- Keep views focused and extract subviews when complexity grows
- Use `@ViewBuilder` for conditional view construction
- Prefer composition over large monolithic views
