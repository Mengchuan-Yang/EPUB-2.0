import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:epub_reader/core/book_parser.dart';
import 'package:epub_reader/core/epub_cfi.dart';
import 'package:epub_reader/core/local_server.dart';

class ReaderView extends StatefulWidget {
  final EpubBookInfo book;
  final LocalServer server;

  const ReaderView({super.key, required this.book, required this.server});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  InAppWebViewController? _webViewController;
  int _currentSpineIndex = 0;
  bool _isLoading = true;
  bool _isControlsVisible = true;
  double _fontSize = 18.0; // font size in px
  String _theme = 'light'; // light, sepia, dark, night
  String _fontFamily = 'default'; // default, serif, sans-serif, monospace
  double _lineHeight = 1.8; // 1.4, 1.8, 2.2
  bool _isAtBottom = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndProgress();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  // Load user settings and last read progress
  Future<void> _loadSettingsAndProgress() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _theme = prefs.getString('reader_theme') ?? 'light';
      _fontSize = prefs.getDouble('reader_font_size') ?? 18.0;
      _fontFamily = prefs.getString('reader_font_family') ?? 'default';
      _lineHeight = prefs.getDouble('reader_line_height') ?? 1.8;
    });

    final cfi = prefs.getString('progress_${widget.book.id}');
    if (cfi != null) {
      final parsed = EpubCfi.parse(cfi);
      if (parsed != null) {
        final spineIndex = parsed['spineIndex'] as int;
        if (spineIndex >= 0 && spineIndex < widget.book.spineHrefs.length) {
          setState(() {
            _currentSpineIndex = spineIndex;
          });
          return;
        }
      }
    }
    // Default fallback
    setState(() {
      _currentSpineIndex = 0;
    });
  }

  // Build the content URL served by our local server
  String get _currentChapterUrl {
    final relPath = widget.book.spineHrefs[_currentSpineIndex];
    return '${widget.server.baseUrl}/${widget.book.id}/extracted/$relPath';
  }

  // Fetch current chapter title based on spineHref
  String get _currentChapterTitle {
    final currentHref = widget.book.spineHrefs[_currentSpineIndex];
    final chapter = widget.book.chapters.firstWhere(
      (c) => c.href == currentHref,
      orElse: () => EpubChapterInfo(title: 'Section ${_currentSpineIndex + 1}', href: ''),
    );
    return chapter.title;
  }

  // Save current progress (EpubCFI) to preferences
  Future<void> _saveProgress() async {
    if (_webViewController == null) return;
    try {
      final elementPath = await _webViewController!.evaluateJavascript(
        source: "window.getVisibleCfi()",
      ) as String?;

      if (elementPath != null && elementPath.isNotEmpty) {
        final cfi = EpubCfi.generate(_currentSpineIndex, '', elementPath);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('progress_${widget.book.id}', cfi);
        print('Saved CFI progress: $cfi');
      }
    } catch (e) {
      print('Error saving progress: $e');
    }
  }

  // Debounced progress saver on scroll
  void _onScroll() {
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveProgress();
      _checkBottomStatus();
    });
  }

  Future<void> _checkBottomStatus() async {
    if (_webViewController == null) return;
    final isBottom = await _webViewController!.evaluateJavascript(
      source: "window.isAtBottom()",
    ) as bool? ?? false;

    if (_isAtBottom != isBottom) {
      setState(() {
        _isAtBottom = isBottom;
      });
    }
  }

  // Update styles in the WebView (font size, theme, text-align, font family, line height)
  void _applyStyles() {
    if (_webViewController == null) return;
    _webViewController!.evaluateJavascript(
      source: "window.applyStyle('$_theme', $_fontSize, '$_fontFamily', $_lineHeight);",
    );
  }

  // Restore scroll offset from last saved EpubCFI
  Future<void> _restoreScrollPosition() async {
    if (_webViewController == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cfi = prefs.getString('progress_${widget.book.id}');
    if (cfi != null) {
      final parsed = EpubCfi.parse(cfi);
      if (parsed != null && parsed['spineIndex'] == _currentSpineIndex) {
        final elementPath = parsed['elementPath'] as String;
        await _webViewController!.evaluateJavascript(
          source: "window.scrollToCfi('$elementPath');",
        );
        print('Restored scroll position to: $elementPath');
      }
    }
  }

  // Go to a specific chapter index
  void _navigateToSpineIndex(int index) {
    if (index < 0 || index >= widget.book.spineHrefs.length) return;
    setState(() {
      _currentSpineIndex = index;
      _isLoading = true;
      _isAtBottom = false;
    });
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_currentChapterUrl)),
    );
  }

  // Inject JavaScript helper functions
  String get _injectedJsHelpers => """
    window.getVisibleCfi = function() {
      function getElementCfi(element) {
        let path = [];
        let current = element;
        while (current && current.nodeType === Node.ELEMENT_NODE && current.nodeName !== 'HTML') {
          let parent = current.parentNode;
          if (!parent) break;
          let siblings = Array.from(parent.children);
          let index = siblings.indexOf(current);
          let cfiIndex = (index + 1) * 2;
          let idStr = current.id ? '[' + current.id + ']' : '';
          path.unshift(cfiIndex + idStr);
          current = parent;
        }
        path.unshift("2");
        return "/" + path.join("/");
      }

      let element = document.body;
      while (element && element.children.length > 0) {
        let foundChild = false;
        for (let child of element.children) {
          let rect = child.getBoundingClientRect();
          if (rect.bottom > 10) {
            element = child;
            foundChild = true;
            break;
          }
        }
        if (!foundChild) break;
      }
      return getElementCfi(element);
    };

    window.scrollToCfi = function(contentPath) {
      if (!contentPath) return;
      contentPath = contentPath.replace(')', '');
      let parts = contentPath.split('/').filter(p => p.length > 0);
      let current = document.documentElement;
      for (let i = 1; i < parts.length; i++) {
        let part = parts[i];
        let match = part.match(/^(\\d+)/);
        if (!match) break;
        let cfiIndex = parseInt(match[1]);
        let elementIndex = (cfiIndex / 2) - 1;
        let children = Array.from(current.children);
        if (elementIndex >= 0 && elementIndex < children.length) {
          current = children[elementIndex];
        } else {
          break;
        }
      }
      if (current) {
        current.scrollIntoView({ behavior: 'auto', block: 'start' });
      }
    };

    window.isAtBottom = function() {
      return (window.innerHeight + window.scrollY) >= document.body.offsetHeight - 80;
    };

    window.applyStyle = function(theme, fontSize, fontFamily, lineHeight) {
      let styleEl = document.getElementById('epub-reader-styles');
      if (!styleEl) {
        styleEl = document.createElement('style');
        styleEl.id = 'epub-reader-styles';
        document.head.appendChild(styleEl);
      }
      
      let bgColor = '#ffffff';
      let textColor = '#1a1a1a';
      if (theme === 'sepia') {
        bgColor = '#fbf0d9';
        textColor = '#3c2f2f';
      } else if (theme === 'dark') {
        bgColor = '#1e1e1e';
        textColor = '#e0e0e0';
      } else if (theme === 'night') {
        bgColor = '#000000';
        textColor = '#808080';
      }
      
      let fontFamilyStyle = '';
      if (fontFamily === 'serif') {
        fontFamilyStyle = 'font-family: Georgia, serif !important;';
      } else if (fontFamily === 'sans-serif') {
        fontFamilyStyle = 'font-family: sans-serif !important;';
      } else if (fontFamily === 'monospace') {
        fontFamilyStyle = 'font-family: monospace !important;';
      }

      styleEl.innerHTML = `
        body, p, div {
            text-align: justify !important;
            text-justify: inter-character !important;
            -webkit-hyphens: auto !important;
            hyphens: auto !important;
            line-break: strict !important;
            word-break: break-word !important;
            font-feature-settings: "chws" 1, "palt" 1 !important;
            text-align-last: left !important;
            line-height: ` + lineHeight + ` !important;
            letter-spacing: 0.03em !important;
            font-size: ` + fontSize + `px !important;
            ` + fontFamilyStyle + `
        }
        body {
            background-color: ` + bgColor + ` !important;
            color: ` + textColor + ` !important;
            padding: 20px 20px 100px 20px !important;
            margin: 0 !important;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
            display: block !important;
            margin: 15px auto !important;
            border-radius: 4px;
        }
        a {
            color: ` + (theme === 'dark' || theme === 'night' ? '#64b5f6' : '#1565c0') + ` !important;
        }
      `;
    };

    document.addEventListener('click', function(e) {
      if (e.target.closest('a') || e.target.closest('img')) return;
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('toggleControls');
      }
    });
  """;

  Widget _buildBottomSheetThemeButton(
    String themeName,
    Color bg,
    Color text,
    String label,
    StateSetter setModalState,
  ) {
    final isSelected = _theme == themeName;
    return GestureDetector(
      onTap: () async {
        setState(() {
          _theme = themeName;
        });
        setModalState(() {});
        _applyStyles();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('reader_theme', themeName);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(color: text, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _buildFontFamilyChip(String familyValue, String label, StateSetter setModalState) {
    final isSelected = _fontFamily == familyValue;
    final isDarkTheme = _theme == 'dark' || _theme == 'night';
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.blue.withOpacity(0.2),
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : textColor,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      showCheckmark: false,
      onSelected: (selected) async {
        if (selected) {
          setState(() {
            _fontFamily = familyValue;
          });
          setModalState(() {});
          _applyStyles();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('reader_font_family', familyValue);
        }
      },
    );
  }

  Widget _buildLineHeightChip(double heightValue, String label, StateSetter setModalState) {
    final isSelected = _lineHeight == heightValue;
    final isDarkTheme = _theme == 'dark' || _theme == 'night';
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.blue.withOpacity(0.2),
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : textColor,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      showCheckmark: false,
      onSelected: (selected) async {
        if (selected) {
          setState(() {
            _lineHeight = heightValue;
          });
          setModalState(() {});
          _applyStyles();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('reader_line_height', heightValue);
        }
      },
    );
  }

  void _showFontSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isDarkTheme = _theme == 'dark' || _theme == 'night';
            final sheetBgColor = isDarkTheme ? const Color(0xFF2C2C2C) : Colors.white;
            final sheetTextColor = isDarkTheme ? Colors.white : Colors.black87;

            return Container(
              decoration: BoxDecoration(
                color: sheetBgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  )
                ],
              ),
              padding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetTextColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '阅读设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: sheetTextColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '背景主题',
                    style: TextStyle(
                      fontSize: 14,
                      color: sheetTextColor.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBottomSheetThemeButton('light', Colors.white, Colors.black87, '明亮', setModalState),
                      _buildBottomSheetThemeButton('sepia', const Color(0xFFFBF0D9), const Color(0xFF3C2F2F), '护眼', setModalState),
                      _buildBottomSheetThemeButton('dark', const Color(0xFF1E1E1E), const Color(0xFFE0E0E0), '暗黑', setModalState),
                      _buildBottomSheetThemeButton('night', Colors.black, Colors.grey, '夜间', setModalState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '字号大小',
                        style: TextStyle(
                          fontSize: 14,
                          color: sheetTextColor.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            color: sheetTextColor,
                            disabledColor: sheetTextColor.withOpacity(0.2),
                            onPressed: _fontSize > 12.0
                                ? () async {
                                    setState(() {
                                      _fontSize -= 2.0;
                                    });
                                    setModalState(() {});
                                    _applyStyles();
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setDouble('reader_font_size', _fontSize);
                                  }
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '${_fontSize.toInt()}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: sheetTextColor,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            color: sheetTextColor,
                            disabledColor: sheetTextColor.withOpacity(0.2),
                            onPressed: _fontSize < 36.0
                                ? () async {
                                    setState(() {
                                      _fontSize += 2.0;
                                    });
                                    setModalState(() {});
                                    _applyStyles();
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setDouble('reader_font_size', _fontSize);
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '字体样式',
                    style: TextStyle(
                      fontSize: 14,
                      color: sheetTextColor.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFontFamilyChip('default', '默认', setModalState),
                      _buildFontFamilyChip('serif', '宋体', setModalState),
                      _buildFontFamilyChip('sans-serif', '黑体', setModalState),
                      _buildFontFamilyChip('monospace', '等宽', setModalState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '行间距',
                    style: TextStyle(
                      fontSize: 14,
                      color: sheetTextColor.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLineHeightChip(1.4, '紧凑', setModalState),
                      _buildLineHeightChip(1.8, '适中', setModalState),
                      _buildLineHeightChip(2.2, '宽松', setModalState),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Get current scaffold background based on theme
  Color get _scaffoldBgColor {
    switch (_theme) {
      case 'sepia':
        return const Color(0xFFFBF0D9);
      case 'dark':
        return const Color(0xFF1E1E1E);
      case 'night':
        return Colors.black;
      case 'light':
      default:
        return Colors.white;
    }
  }

  // Get text color for overlays based on reading theme
  Color get _overlayTextColor {
    return (_theme == 'dark' || _theme == 'night') ? Colors.white : Colors.black87;
  }

  // Get background color for control overlays
  Color get _overlayBgColor {
    return (_theme == 'dark' || _theme == 'night')
        ? const Color(0xFF2C2C2C).withOpacity(0.95)
        : Colors.white.withOpacity(0.95);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _scaffoldBgColor,
      drawer: _buildTOCDrawer(),
      body: Stack(
        children: [
          // WebView Container
          GestureDetector(
            onTap: () {
              setState(() {
                _isControlsVisible = !_isControlsVisible;
              });
            },
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentChapterUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                verticalScrollBarEnabled: true,
                horizontalScrollBarEnabled: false,
                transparentBackground: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'toggleControls',
                  callback: (args) {
                    setState(() {
                      _isControlsVisible = !_isControlsVisible;
                    });
                  },
                );
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (controller, url) async {
                // Inject JS helpers and setup styling
                await controller.evaluateJavascript(source: _injectedJsHelpers);
                _applyStyles();
                await _restoreScrollPosition();
                setState(() {
                  _isLoading = false;
                });
              },
              onScrollChanged: (controller, x, y) {
                _onScroll();
              },
            ),
          ),

          // Top Header Overlay
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _isControlsVisible ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                color: _overlayBgColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios, color: _overlayTextColor),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.book.title,
                      style: TextStyle(
                        fontSize: 14,
                        color: _overlayTextColor.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentChapterTitle,
                      style: TextStyle(
                        fontSize: 16,
                        color: _overlayTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.menu, color: _overlayTextColor),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Control Overlay
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _isControlsVisible ? 0 : -150,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 28),
              decoration: BoxDecoration(
                color: _overlayBgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 16,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Chapter Pagination Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.skip_previous, color: _overlayTextColor),
                        onPressed: _currentSpineIndex > 0
                            ? () => _navigateToSpineIndex(_currentSpineIndex - 1)
                            : null,
                      ),
                      Text(
                        '${_currentSpineIndex + 1} / ${widget.book.spineHrefs.length}',
                        style: TextStyle(color: _overlayTextColor, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: _overlayTextColor),
                        onPressed: _currentSpineIndex < widget.book.spineHrefs.length - 1
                            ? () => _navigateToSpineIndex(_currentSpineIndex + 1)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Bottom Action Buttons (TOC and Font Settings)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          foregroundColor: _overlayTextColor,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: Icon(Icons.menu, size: 20, color: _overlayTextColor),
                        label: Text('章节目录', style: TextStyle(color: _overlayTextColor, fontSize: 14, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          setState(() {
                            _isControlsVisible = false;
                          });
                          _scaffoldKey.currentState?.openDrawer();
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          foregroundColor: _overlayTextColor,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: Icon(Icons.text_fields, size: 20, color: _overlayTextColor),
                        label: Text('排版与主题', style: TextStyle(color: _overlayTextColor, fontSize: 14, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          setState(() {
                            _isControlsVisible = false;
                          });
                          _showFontSettingsBottomSheet(context);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Loading Indicator
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),

          // Bottom Floating 'Next Chapter' Button (when scrolled to bottom)
          if (!_isLoading && _isAtBottom && _currentSpineIndex < widget.book.spineHrefs.length - 1)
            Positioned(
              bottom: _isControlsVisible ? 170 : 30,
              left: 50,
              right: 50,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: 1.0,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 6,
                    ),
                    icon: const Icon(Icons.navigate_next),
                    label: const Text('载入下一章', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onPressed: () {
                      _navigateToSpineIndex(_currentSpineIndex + 1);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Sidebar Table of Contents Drawer
  Widget _buildTOCDrawer() {
    return Drawer(
      backgroundColor: _scaffoldBgColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                '目录',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _overlayTextColor,
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: widget.book.chapters.length,
                itemBuilder: (context, idx) {
                  final chapter = widget.book.chapters[idx];
                  // Determine if this chapter matches the current spine file
                  final isCurrent = widget.book.spineHrefs[_currentSpineIndex] == chapter.href;

                  return ListTile(
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        color: isCurrent ? Colors.blue : _overlayTextColor,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isCurrent ? const Icon(Icons.bookmark_added, color: Colors.blue) : null,
                    onTap: () {
                      Navigator.of(context).pop(); // close drawer
                      // Find which spine index corresponds to this chapter href
                      final spineIdx = widget.book.spineHrefs.indexOf(chapter.href);
                      if (spineIdx != -1) {
                        _navigateToSpineIndex(spineIdx);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

