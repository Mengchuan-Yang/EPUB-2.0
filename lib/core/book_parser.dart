import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EpubChapterInfo {
  final String title;
  final String href; // Relative to the unzipped root (includes opfDir prefix)

  EpubChapterInfo({required this.title, required this.href});

  Map<String, dynamic> toJson() => {
        'title': title,
        'href': href,
      };

  factory EpubChapterInfo.fromJson(Map<String, dynamic> json) => EpubChapterInfo(
        title: json['title'] as String,
        href: json['href'] as String,
      );
}

class EpubBookInfo {
  final String id;
  final String title;
  final String author;
  final String coverPath;
  final String epubFilePath;
  final String extractedDir;
  final String opfDir; // E.g., "OEBPS/" or ""
  final List<EpubChapterInfo> chapters;
  final List<String> spineHrefs; // Order of all spine files (relative to unzipped root)

  EpubBookInfo({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.epubFilePath,
    required this.extractedDir,
    required this.opfDir,
    required this.chapters,
    required this.spineHrefs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'coverPath': coverPath,
        'epubFilePath': epubFilePath,
        'extractedDir': extractedDir,
        'opfDir': opfDir,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'spineHrefs': spineHrefs,
      };

  factory EpubBookInfo.fromJson(Map<String, dynamic> json) => EpubBookInfo(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String,
        coverPath: json['coverPath'] as String,
        epubFilePath: json['epubFilePath'] as String,
        extractedDir: json['extractedDir'] as String,
        opfDir: json['opfDir'] as String,
        chapters: (json['chapters'] as List)
            .map((c) => EpubChapterInfo.fromJson(c as Map<String, dynamic>))
            .toList(),
        spineHrefs: List<String>.from(json['spineHrefs'] as List),
      );
}

class BookParser {
  static Future<String> get _booksDir async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'books'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<File> get _dbFile async {
    final dir = await _booksDir;
    return File(p.join(dir, 'books.json'));
  }

  // Load all imported books
  static Future<List<EpubBookInfo>> loadBooks() async {
    try {
      final file = await _dbFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List list = jsonDecode(content) as List;
      return list.map((json) => EpubBookInfo.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading books: $e');
      return [];
    }
  }

  // Save all books
  static Future<void> _saveBooks(List<EpubBookInfo> books) async {
    final file = await _dbFile;
    final content = jsonEncode(books.map((b) => b.toJson()).toList());
    await file.writeAsString(content);
  }

  // Import a new book from path
  static Future<EpubBookInfo> importEpub(String srcPath) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final booksPath = await _booksDir;
    final bookFolder = Directory(p.join(booksPath, id));
    await bookFolder.create(recursive: true);

    // 1. Copy original EPUB file
    final destEpubPath = p.join(bookFolder.path, 'book.epub');
    final srcFile = File(srcPath);
    await srcFile.copy(destEpubPath);

    // 2. Unzip the EPUB file to extracted/
    final extractedDirPath = p.join(bookFolder.path, 'extracted');
    final extractedDir = Directory(extractedDirPath);
    await extractedDir.create(recursive: true);

    final bytes = await srcFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File(p.join(extractedDirPath, filename));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data, flush: true);
      }
    }

    // 3. Find the OPF file to determine opfDir
    String opfDir = '';
    await for (final entity in extractedDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.opf')) {
        final relPath = p.relative(entity.path, from: extractedDirPath);
        if (relPath.contains(Platform.pathSeparator)) {
          final parts = relPath.split(Platform.pathSeparator);
          parts.removeLast(); // Remove the opf file name itself
          opfDir = '${parts.join('/')}/';
        } else if (relPath.contains('/')) {
          final parts = relPath.split('/');
          parts.removeLast();
          opfDir = '${parts.join('/')}/';
        }
        break;
      }
    }

    // 4. Parse EPUB using epubx package
    final epubBook = await EpubReader.readBook(bytes);
    final title = epubBook.Title ?? p.basenameWithoutExtension(srcPath);
    final author = epubBook.Author ?? 'Unknown Author';

    // 5. Extract cover image if present
    String coverPath = '';
    if (epubBook.CoverImage != null) {
      try {
        final coverBytes = img_lib.encodePng(epubBook.CoverImage!);
        final coverFile = File(p.join(bookFolder.path, 'cover.png'));
        await coverFile.writeAsBytes(coverBytes);
        coverPath = coverFile.path;
      } catch (e) {
        print('Error saving cover image: $e');
      }
    }

    // 6. Map spine items (order of files)
    final List<String> spineHrefs = [];
    final spineItems = epubBook.Schema?.Package?.Spine?.Items ?? [];
    final manifestItems = epubBook.Schema?.Package?.Manifest?.Items ?? [];

    for (final spine in spineItems) {
      final idref = spine.IdRef;
      final manifestItem = manifestItems.firstWhere(
        (m) => m.Id == idref,
        orElse: () => EpubManifestItem(),
      );
      if (manifestItem.Href != null) {
        // Spine hrefs are relative to the OPF file.
        // We prepend the opfDir to make them relative to the extracted root directory.
        final fullHref = opfDir + manifestItem.Href!;
        spineHrefs.add(fullHref);
      }
    }

    // 7. Flatten and map chapters (TOC)
    final List<EpubChapterInfo> chapters = [];
    void extractChapters(List<EpubChapter> epubChapters) {
      for (final ch in epubChapters) {
        if (ch.ContentFileName != null) {
          final fullHref = opfDir + ch.ContentFileName!;
          chapters.add(EpubChapterInfo(
            title: ch.Title ?? 'Chapter ${chapters.length + 1}',
            href: fullHref,
          ));
        }
        if (ch.SubChapters != null && ch.SubChapters!.isNotEmpty) {
          extractChapters(ch.SubChapters!);
        }
      }
    }

    if (epubBook.Chapters != null) {
      extractChapters(epubBook.Chapters!);
    }

    // If chapters list is empty, fallback to spine items
    if (chapters.isEmpty) {
      for (int i = 0; i < spineHrefs.length; i++) {
        chapters.add(EpubChapterInfo(
          title: 'Section ${i + 1}',
          href: spineHrefs[i],
        ));
      }
    }

    // 8. Create Book Info
    final bookInfo = EpubBookInfo(
      id: id,
      title: title,
      author: author,
      coverPath: coverPath,
      epubFilePath: destEpubPath,
      extractedDir: extractedDirPath,
      opfDir: opfDir,
      chapters: chapters,
      spineHrefs: spineHrefs,
    );

    // 9. Add to DB and save
    final books = await loadBooks();
    books.add(bookInfo);
    await _saveBooks(books);

    return bookInfo;
  }

  // Delete a book
  static Future<void> deleteBook(String id) async {
    final books = await loadBooks();
    books.removeWhere((b) => b.id == id);
    await _saveBooks(books);

    final booksPath = await _booksDir;
    final bookFolder = Directory(p.join(booksPath, id));
    if (await bookFolder.exists()) {
      await bookFolder.delete(recursive: true);
    }
  }
}
