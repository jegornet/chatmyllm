# chatmyllm - Architecture & Implementation Notes

## Overview
chatmyllm is a native macOS chat application built with SwiftUI that interfaces with various LLM models through the OpenRouter API. The app provides a ChatGPT-like experience with support for multiple models, chat history persistence, and real-time streaming responses.

## Architecture

### Core Technologies
- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Native persistence layer (replacement for Core Data)
- **OpenRouter API** - LLM model provider with streaming support
- **Combine** - Reactive framework (minimal usage, mostly SwiftUI bindings)

### App Structure

```
chatmyllm/
├── chatmyllmApp.swift          # App entry point, ModelContainer setup
├── ContentView.swift            # Main split view, EmptyStateView
├── ChatListView.swift           # Sidebar with chat list
├── ChatDetailView.swift         # Main chat view with messages and input
├── Models.swift                 # SwiftData models (Chat, Message)
├── OpenRouterService.swift      # API service with streaming support
├── SettingsManager.swift        # Observable settings singleton
├── SettingsView.swift           # Settings UI (API key, fonts, models)
└── Localizable.xcstrings        # Localization (EN/RU)
```

## Data Models

### Chat
- `id: UUID` - Unique identifier
- `title: String` - Chat title (auto-generated from first message)
- `createdAt: Date` - Creation timestamp
- `modelId: String` - Selected LLM model ID
- `draft: String` - Unsaved draft message
- `messages: [Message]` - Relationship to messages (cascade delete)

### Message
- `id: UUID` - Unique identifier
- `content: String` - Message text (supports Markdown)
- `isFromUser: Bool` - Message sender
- `timestamp: Date` - Message timestamp
- `chat: Chat?` - Inverse relationship

## Key Features

### 1. Streaming API Implementation
**Decision:** Real-time streaming for better UX, showing LLM responses as they generate.

**Implementation:**
- `OpenRouterService.sendMessageStreaming()` uses `URLSession.bytes(for:)` for async streaming
- Server-Sent Events (SSE) parsing: reads line by line, decodes JSON chunks
- UTF-8 handling: accumulates bytes in `Data` buffer before decoding (fixes multi-byte character issues)
- State management: `streamingContent` accumulates chunks, `isStreaming` controls UI
- Chat isolation: `streamingChatId` ensures streaming only affects the originating chat

**Challenges Solved:**
- UTF-8 encoding: Initially processed bytes one-by-one causing corruption for non-ASCII characters. Fixed by buffering until newline.
- Chat isolation: Streaming continued in wrong chat when switching. Fixed by tracking `streamingChatId` and checking it in all streaming-related UI.

### 2. Chat Isolation
**Problem:** When user switches chats during streaming, the stream would "leak" into the new chat.

**Solution:**
- Store `streamingChatId: UUID?` when streaming starts
- Check `streamingChatId == chat.id` before showing streaming UI elements
- Cancel streaming task in `.onDisappear` if chat matches `streamingChatId`
- Save partial response to correct chat before cleanup

### 3. Settings Management
**Decision:** Observable singleton pattern with UserDefaults persistence.

**Implementation:**
```swift
@Observable class SettingsManager {
    static let shared = SettingsManager()

    var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }
    // ... other properties
}
```

**Why Observable over ObservableObject:**
- Modern Swift concurrency support
- Simpler syntax with `@Observable` macro
- Better performance (fine-grained observation)

**Live Updates:**
- Settings changes apply immediately without closing settings window
- Use `@Bindable` in SettingsView for two-way bindings
- Direct property observation in main UI

### 4. Auto-Scroll Behavior
**Requirements:**
- Scroll to bottom when opening a chat
- Auto-scroll during streaming responses
- Scroll to final message when streaming completes
- Scroll to final message when user stops streaming
- Maintain scroll position when switching chats
- Hide scroll indicators during streaming to avoid jittery appearance

**Implementation:**
- `ScrollViewReader` with saved `scrollProxy`
- `.defaultScrollAnchor(.bottom)` for initial positioning at bottom
- `.id(chat.id)` forces ScrollView recreation on chat change
- `.onChange(of: streamingContent)` triggers throttled scroll during streaming (max 3 updates/sec)
- `.scrollIndicators(.hidden)` during streaming, `.visible` otherwise
- Final scroll after streaming completion/stop to ensure message is visible
- Smooth animations with `.easeOut(duration: 0.2-0.3)`

**Critical Fix:**
LazyVStack's prefetch system conflicts with frequent view updates during streaming. Original implementation crashed with `EXC_BREAKPOINT` in `LazyLayoutViewCacheC14signalPrefetchyyFyycfU_`. Root cause: `StreamingMessageView` was **inside LazyVStack**, and each streaming chunk update (100-1000/sec) triggered LazyVStack's prefetch recalculation. Fixed by:
1. **Moving StreamingMessageView outside LazyVStack** - wrapped in regular VStack, so streaming updates don't affect LazyVStack's prefetch
2. LazyVStack now only contains static messages that don't change during streaming
3. Auto-scroll is now safe with throttling (0.3 sec intervals) because updates happen outside LazyVStack
4. Using fixed height for TextEditor (`.frame(height: 100)`) instead of dynamic recalculation

### 5. Input Field Focus Management
**Behavior:**
- Focus on first chat selection
- Focus on subsequent chat switches
- Focus after streaming completes
- Focus after stopping stream with Stop button
- No focus during streaming (but input remains enabled)

**Implementation:**
- `.onAppear` with delay for initial focus
- `.onChange(of: chat.id)` for chat switches
- `isInputFocused = true` after streaming completion
- Input field never disabled (only Enter key blocked during streaming)

### 6. Markdown Rendering
**Decision:** Custom parser for code blocks, native AttributedString for inline formatting.

**Rationale:**
- Native markdown rendering doesn't support custom code block styling
- Need monospaced font and different colors for code
- Preserve whitespace in code blocks

**Implementation:**
- Parse triple backtick code blocks manually
- Parse single backtick inline code
- Use `AttributedString(markdown:)` for bold, italic, links
- Custom `MarkdownText` view combines all parts

### 7. Model Selection
**Features:**
- Load available models from OpenRouter API
- Filter to enabled models (user-selected in settings)
- Per-chat model selection
- Default model for new chats

**UX Decisions:**
- Model picker in toolbar (always visible)
- Disabled during streaming to prevent mid-stream model change
- Search in settings for finding models
- Enabled/disabled toggle for model management

### 8. First Message Flow
**Requirement:** New chat should stream immediately without "creating then sending" delay.

**Solution:**
- EmptyStateView creates chat with user message
- Immediately switches to ChatDetailView
- ChatDetailView detects new chat (last message from user) in `.onAppear`
- Auto-sends with `sendMessage(autoSend: true)` parameter
- Streaming starts immediately, user sees response generation

## Technical Decisions

### Why SwiftData over Core Data?
- Modern Swift-first API
- Macro-based models (less boilerplate)
- Better type safety
- Native async/await support

### Why @Observable over @ObservableObject?
- Part of Swift 5.9+ observation framework
- More efficient change notifications
- Cleaner syntax
- Better SwiftUI integration

### Why Store Draft in Chat Model?
- Persist unsent messages across app restarts
- Natural data model (draft belongs to chat)
- Automatic save/restore

### Why Per-Chat Model Selection?
- Different models have different strengths
- User might want to compare model outputs
- Flexibility for power users

### Why LazyVStack for Messages + VStack for Streaming?
- **LazyVStack for messages:** Only renders visible messages, critical for chats with hundreds of messages
- **Regular VStack wrapper:** Allows streaming view outside LazyVStack to avoid prefetch conflicts
- **Streaming view in VStack:** Frequent updates don't trigger LazyVStack recalculation
- Combined with `.id(chat.id)` for proper reset on chat switch

### Why Separate Streaming from Regular API Call?
- Different response formats (SSE vs JSON)
- Better UX with streaming
- Easier to maintain separate code paths
- Keep non-streaming as fallback

## State Management

### Global State
- `SettingsManager.shared` - App settings (Observable singleton)

### View State
- `@State` for local view state (isLoading, errorMessage)
- `@Bindable` for two-way bindings to Observable objects
- `@Environment(\.modelContext)` for SwiftData access
- `@FocusState` for input field focus

### Streaming State
- `isStreaming: Bool` - Currently streaming
- `streamingContent: String` - Accumulated response
- `streamingTask: Task?` - Cancellable task reference
- `streamingChatId: UUID?` - Which chat is streaming

## UI/UX Patterns

### NavigationSplitView
Three-column layout:
1. Sidebar: Chat list
2. Detail: Chat messages + input (or EmptyStateView)
3. No inspector pane

### Keyboard Shortcuts
- `Cmd+N` - New chat
- `Enter` - Send message (blocked during streaming)
- `Shift+Enter` - New line in message

### Visual Feedback
- Blue bubble for user messages
- Gray bubble for assistant messages
- Blue stop button during streaming
- Disabled model picker during streaming
- Semi-transparent toolbar background

### Accessibility
- Proper focus management
- Keyboard navigation
- VoiceOver support through SwiftUI defaults

## Error Handling

### API Errors
- Display in-line error messages (orange warning)
- Don't crash on network errors
- Preserve partial streaming responses
- Allow retry

### Data Errors
- Fatal error on ModelContainer creation (can't recover)
- Graceful handling of missing models
- Default to safe values for missing settings

## Performance Considerations

### LazyVStack
- Only renders visible messages
- Critical for performance with long chats

### Streaming Chunk Processing
- Process on background thread
- Update UI on MainActor
- Efficient string concatenation

### Settings Updates
- didSet observers minimize UserDefaults writes
- No unnecessary view updates

## Future Considerations

### Potential Improvements
1. **Attachments** - Image support
2. **Export** - Export chat to Markdown/PDF
3. **Search** - Search across all chats
4. **Folders** - Organize chats
5. **Themes** - Dark/light mode customization
6. **Shortcuts** - macOS Shortcuts integration
7. **Context** - Manage context window
8. **Tools** - Function calling support

### Known Limitations
1. No image support (text-only)
2. No conversation branching
3. No chat templates
4. No model comparison view
5. Single-window only

## Building & Distribution

### Requirements
- macOS 15.0+ (SwiftUI features)
- Xcode 17.0+
- Swift 6.0+

### Build Configurations
- Debug: Development with preview support
- Release: Optimized for distribution

### Distribution
- DMG file for direct download
- Signed with Apple Developer certificate
- No Mac App Store (API key requirement)

## Version History

### 0.1 (Initial Release)
- Basic chat functionality
- Model selection
- Settings management
- Localization (EN/RU)

### 0.2 (Streaming Update)
- Real-time streaming responses
- Stop button to cancel generation
- Per-chat streaming isolation
- Improved focus management
- UTF-8 encoding fixes
- Fixed critical crash in LazyVStack by moving `StreamingMessageView` outside of LazyVStack (frequent updates were triggering prefetch recalculation)
- Fixed height input field (100pt) instead of dynamic recalculation
- Hybrid layout: LazyVStack for messages, regular VStack wrapper for streaming content
- Auto-scroll during streaming with throttling (max 3 updates/sec)
- Scroll to final message after streaming completes or stops
- Hidden scroll indicators during streaming to prevent jittery appearance

## Development Notes

### Common Pitfalls
1. **Focus not working:** Add delay in DispatchQueue.main.asyncAfter
2. **Streaming in wrong chat:** Check streamingChatId
3. **UTF-8 corruption:** Buffer bytes before String conversion
4. **Scroll not working:** Ensure .id() on ScrollView for reset
5. **Settings not updating:** Use @Bindable not @State copy
6. **LazyVStack constraint crash:** Never put frequently-updating views (like streaming content) inside LazyVStack - wrap in VStack and place streaming view outside LazyVStack; use fixed height for input fields

### Debugging Tips
- Check streaming state: isStreaming, streamingChatId, streamingContent
- Verify ModelContext injection in environment
- Use Xcode previews with in-memory container
- Test chat switching during streaming
- Test with long messages (scroll behavior)

### Code Style
- SwiftUI declarative style
- Minimal comments (self-documenting code)
- Grouped modifiers logically
- Extract complex views into separate structs
- Use extensions for computed properties

---

**Last Updated:** March 16, 2026 (Version 0.2)
