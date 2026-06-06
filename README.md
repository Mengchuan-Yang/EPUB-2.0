# EPUB Flow Reader (EPUB 流式阅读器)

An advanced, elegant, and flow-based Android EPUB reader built with Flutter. Designed for a web-like seamless scrolling experience with modern typography controls, pinch-to-zoom font scaling, and immersive fullscreen reading.

一款基于 Flutter 构建的高级、优雅且流式排版的 Android EPUB 阅读器。专为网页般流畅滚动的阅读体验而设计，支持现代化版面及主题配置、双指缩放字号重排，以及完全沉浸式全屏阅读。

---

## 🚀 Key Features / 核心功能

### 1. Web-like Flow Layout (网页级流式排版)
- **Fluid Scrolling**: Reads EPUB content as a continuous scrolling page, mimicking modern web browsers for seamless reading.
- **流畅滚动**：将 EPUB 内容渲染为连续滚动的页面，模拟现代化网页浏览，带来无缝的阅读体验。
- **Justified Alignment**: Optimized Chinese and English text alignment (word-break, hyphenation, character spacing) for premium reading aesthetics.
- **两端对齐**：针对中英文排版进行了特殊优化（自动折行、连字符、字符间距），确保极佳的文本视觉美感。

### 2. Double-Finger Pinch Scaling & Reflow (双指缩放与重排)
- **Reflowable Text Zoom**: Double-finger pinch gesture on the screen dynamically scales the text font size (from 12px to 45px) with real-time layout reflow.
- **双指手势缩放**：直接双指在屏幕上捏合即可实时调整字号大小（12px 至 45px），且排版实时自动重排。
- **Image Bounds Locking**: Keeps all embedded book images constrained inside the viewport width (`max-width: 100%`) so images never stretch off-screen.
- **图片边界约束**：所有嵌入的图书图片都被锁定在屏幕可视宽度内（`max-width: 100%`），缩放文字时图片绝不会超出屏幕边界。
- **Size Persistence**: Automatically saves and remembers the scaled font size across reading sessions.
- **字号记忆**：自动保存双指缩放的字号大小，再次打开应用或切换章节时自动恢复。

### 3. Immersive Fullscreen Mode (完全沉浸式阅读)
- **Zero-Distraction Reading**: Automatically hides the Android system status bar and navigation bar (`immersiveSticky` mode) and all reader controls by default.
- **无干扰阅读**：默认自动隐藏 Android 系统状态栏、导航栏（`immersiveSticky` 模式）以及阅读器的所有控制面板，呈现最干净的书页。
- **Single-Tap Toggle**: Tap the screen center to smoothly toggle the visibility of the compact custom control bars and system overlays simultaneously.
- **单击切换**：轻触阅读区域即可平滑地同时唤出/隐藏系统栏和阅读器控制面板。
- **Notch & Camera Safe**: WebView padding is mathematically adjusted (top padding `50px`) to ensure content is never cut off or obscured by physical camera notches or hole-punches.
- **完美适配刘海屏**：WebView 顶部留有 `50px` 边距，确保即使在有物理挖孔或刘海的屏幕上，正文内容也绝不会被物理遮挡。
- **No Running Headers**: Automatically injects CSS to hide publisher-bundled running headers and page numbers (like `.runningheader`, `.epub-header`), removing redundant visual clutter.
- **隐藏页眉页脚**：自动注入 CSS 规则过滤并隐藏书籍自带的页眉/页脚小标题（如 `.runningheader`、`.epub-header` 等），只留下纯净书页。

### 4. Custom Compact Controls & Theming (紧凑型控制栏与主题)
- **Ultra-Compact Bar**: Uses a custom, sleek `Row` design (height ~90px including status bar padding) instead of default tall `AppBar` widgets, saving massive screen real estate.
- **极简紧凑菜单**：采用自定义的极简 `Row` 导航栏（包含刘海间距高度仅约 90px），替换了占用空间极大的默认 `AppBar`，极大地释放了可视面积。
- **Themed Controls**: Background colors (`_overlayBgColor`) and text colors (`_overlayTextColor`) of the UI overlays perfectly blend with the reading themes using solid premium colors:
- **主题化配色**：控制面板的背景色及前景色会根据当前的阅读主题自动适配，呈现完美的沉浸美学：
  - **Light (明亮)**: Pure white theme / 纯白背景，深灰文字。
  - **Sepia (护眼)**: Warm cream background (`Color(0xFFF5EACF)`) / 暖沙黄背景，深褐文字 (`Color(0xFF3C2F2F)`)。
  - **Dark (暗黑)**: Cool grey background (`Color(0xFF2C2C2C)`) / 深灰背景，浅灰文字 (`Color(0xFFE0E0E0)`)。
  - **Night (夜间)**: Pitch black background (`Color(0xFF121212)`) / 纯黑背景，暗灰文字 (`Color(0xFF808080)`)。

### 5. Local Sandboxed Server & CFI Tracking (本地沙箱服务与进度追踪)
- **Zero-CORS Embedded Server**: Features a built-in lightweight local server in [local_server.dart](lib/core/local_server.dart) to bypass CORS and securely serve extracted EPUB assets.
- **本地零跨域服务器**：内置轻量级本地服务器，绕过 CORS 跨域限制，安全地渲染解压后的 EPUB 书籍资源。
- **EpubCFI Precise Progress**: Saves exact reading positions using EpubCFI standards, restoring the precise scroll offset when reloading a book.
- **精准进度追踪**：采用 EpubCFI 标准记录阅读位置，重新打开书籍时精准恢复到上次阅读的滚动行。

---

## 📅 Version History & Changelog / 历史版本记录

### v1.1.0 (Current Release / 当前版本)
> **Reflow Scale & Immersive Fullscreen Release / 缩放重排与完全沉浸版**
- **[New]** Added pinch-to-zoom gesture on the WebView to scale font sizes dynamically (12px - 45px) with automatic layout reflow.
- **[新增]** WebView 双指缩放字号（12px - 45px）及版面实时重排功能。
- **[New]** Implemented full system `immersiveSticky` fullscreen mode. Hiding status/navigation bars by default.
- **[新增]** 系统级 `immersiveSticky` 完全沉浸式全屏，默认隐藏状态栏与虚拟键。
- **[New]** Custom, ultra-compact top overlay bar (height 50px + status bar padding) replacing heavy `AppBar` to save vertical screen space.
- **[新增]** 紧凑型顶部状态栏（去除 heavy AppBar，实际内容高度仅 50px），极大释放了屏幕显示空间。
- **[Fix]** Fixed notch/cut-out blocking issue by increasing body padding-top to `50px` and injecting CSS rules to hide redundant publisher running headers.
- **[修复]** 修复刘海屏/挖孔屏遮挡正文问题：增加 `50px` 顶部边距，并注入 CSS 过滤并隐藏书籍自身的页眉页脚小标题。
- **[Theme]** Added theme-adaptive solid styling backgrounds (Light, Sepia, Dark, Night) for control menus.
- **[优化]** 支持控制菜单（加字号、换主题等面板）的全局配色主题适配（明亮、护眼、暗黑、夜间）。

### v1.0.0
> **Initial MVP Release / 基础 MVP 版**
- **[Feat]** Added basic EPUB importing and metadata extraction (title, author, cover, spine).
- **[新增]** 基础 EPUB 导入及元数据解析（书名、作者、封面、骨架文件）。
- **[Feat]** Implemented local sandboxed HTTP server for secure EPUB assets extraction and bypass of CORS constraints.
- **[新增]** 本地沙箱 HTTP 服务器，安全提取并运行 EPUB 静态资源，规避跨域限制。
- **[Feat]** Built Table of Contents (TOC) drawer navigation.
- **[新增]** 基础侧边栏目录（TOC）导航抽屉。
- **[Feat]** Basic EpubCFI progress persistence using `SharedPreferences`.
- **[新增]** 基础 EpubCFI 阅读进度存储，借助 `SharedPreferences` 实现退出记忆。

---

## 🛠️ Build & Compilation / 构建与编译

### Requirements / 构建环境
- Flutter SDK `^3.12.1`
- Android SDK (targeting API level 36)
- Connected Android device (e.g. Pixel 9 Pro XL) or Emulator

### Steps / 编译步骤
1. Clone the repository and navigate to the project directory:
   ```bash
   git clone https://github.com/Mengchuan-Yang/EPUB-2.0.git
   cd EPUB-2.0
   ```
2. Retrieve dependencies:
   ```bash
   flutter pub get
   ```
3. Run code analysis:
   ```bash
   flutter analyze
   ```
4. Build release APK:
   ```bash
   flutter build apk --release
   ```
5. Deploy and install to connected device via ADB:
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```
