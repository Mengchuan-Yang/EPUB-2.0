import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:epub_reader/core/book_parser.dart';
import 'package:epub_reader/core/epub_cfi.dart';
import 'package:epub_reader/core/local_server.dart';
import 'package:epub_reader/reader/reader_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EpubReaderApp());
}

class EpubReaderApp extends StatelessWidget {
  const EpubReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '沉浸式流式阅读器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3E50),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C3E50),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.system,
      home: const BookshelfView(),
    );
  }
}

class BookshelfView extends StatefulWidget {
  const BookshelfView({super.key});

  @override
  State<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends State<BookshelfView> {
  List<EpubBookInfo> _books = [];
  Map<String, double> _progressMap = {}; // BookId -> Progress (0.0 to 1.0)
  LocalServer? _server;
  bool _isServerReady = false;
  bool _isImporting = false;
  bool _isLoadingBooks = true;

  @override
  void initState() {
    super.initState();
    _initServerAndLoadBooks();
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  // Initialize the local server and load books
  Future<void> _initServerAndLoadBooks() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final booksDir = p.join(docDir.path, 'books');
      
      // Ensure the books directory exists
      final dir = Directory(booksDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Initialize and start local HTTP server
      _server = LocalServer(booksDir);
      await _server!.start();

      setState(() {
        _isServerReady = true;
      });

      await _refreshBooks();
    } catch (e) {
      print('Error initializing app: $e');
    }
  }

  // Refresh book list and load progress percentages
  Future<void> _refreshBooks() async {
    setState(() {
      _isLoadingBooks = true;
    });

    final books = await BookParser.loadBooks();
    final progressMap = <String, double>{};
    final prefs = await SharedPreferences.getInstance();

    for (final book in books) {
      final cfi = prefs.getString('progress_${book.id}');
      if (cfi != null && book.spineHrefs.isNotEmpty) {
        final parsed = EpubCfi.parse(cfi);
        if (parsed != null) {
          final spineIndex = parsed['spineIndex'] as int;
          progressMap[book.id] = (spineIndex / book.spineHrefs.length);
        } else {
          progressMap[book.id] = 0.0;
        }
      } else {
        progressMap[book.id] = 0.0;
      }
    }

    setState(() {
      _books = books;
      _progressMap = progressMap;
      _isLoadingBooks = false;
    });
  }

  // Import EPUB action
  Future<void> _importEpub() async {
    if (_isImporting) return;
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isImporting = true;
        });

        final path = result.files.single.path!;
        await BookParser.importEpub(path);
        await _refreshBooks();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('书籍导入成功！'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print('Error importing EPUB: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  // Confirm delete dialog
  Future<void> _deleteBook(EpubBookInfo book) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('您确定要删除《${book.title}》吗？这将清除所有阅读记录。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await BookParser.deleteBook(book.id);
      await _refreshBooks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书籍已删除')),
      );
    }
  }

  // UI styling helper: Generate color based on title hash for cover placeholder
  LinearGradient _generateGradient(String title) {
    final hash = title.hashCode;
    final hue1 = (hash % 360).toDouble();
    final hue2 = ((hash + 120) % 360).toDouble();
    return LinearGradient(
      colors: [
        HSVColor.fromAHSV(1.0, hue1, 0.65, 0.45).toColor(),
        HSVColor.fromAHSV(1.0, hue2, 0.55, 0.35).toColor(),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '我的书架',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshBooks,
          )
        ],
      ),
      body: Stack(
        children: [
          // Main Body
          _isLoadingBooks
              ? const Center(child: CircularProgressIndicator())
              : _books.isEmpty
                  ? _buildEmptyState()
                  : _buildBooksGrid(),

          // Importing overlay dialog
          if (_isImporting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          '正在导入书籍...',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '解压排版及构建索引中，请稍候',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importEpub,
        icon: const Icon(Icons.add),
        label: const Text('导入书籍', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }

  // Beautiful empty state placeholder
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '书架空空如也',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '点击右下角按钮导入电子书\n开始您的沉浸式流式阅读体验',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Responsive Book Cover Grid
  Widget _buildBooksGrid() {
    final width = MediaQuery.of(context).size.width;
    // Calculate dynamic cross axis count (2 on phones, more on tablets)
    final crossAxisCount = (width / 160).floor().clamp(2, 6);

    return GridView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 90),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        final progress = _progressMap[book.id] ?? 0.0;
        final hasCover = book.coverPath.isNotEmpty && File(book.coverPath).existsSync();

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () {
              if (!_isServerReady || _server == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('服务器尚未就绪，请稍等...')),
                );
                return;
              }
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (context) => ReaderView(book: book, server: _server!),
                ),
              )
                  .then((_) {
                // Refresh progress when returning to bookshelf
                _refreshBooks();
              });
            },
            onLongPress: () => _deleteBook(book),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover Image / Placeholder
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: hasCover
                            ? Image.file(
                                File(book.coverPath),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: _generateGradient(book.title),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    book.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(0, 1),
                                          blurRadius: 4,
                                          color: Colors.black54,
                                        )
                                      ],
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                      ),
                      // Top dark tint for controls representation
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onPressed: () => _deleteBook(book),
                        ),
                      ),
                      // Progress overlay bar at bottom of cover
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.black26,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blueAccent.withOpacity(0.9),
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                // Metadata block
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              book.author,
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
