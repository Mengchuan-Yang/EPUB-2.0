class EpubCfi {
  /// Generates a standard EpubCFI string.
  /// [spineIndex] is 0-based.
  /// [chapterId] is the manifest ID of the chapter (can be empty).
  /// [elementPath] is the path inside the document, e.g., `/2/4/6/8`.
  static String generate(int spineIndex, String chapterId, String elementPath) {
    final spineNum = (spineIndex + 1) * 2;
    final idPart = chapterId.isNotEmpty ? '[$chapterId]' : '';
    // Ensure elementPath starts with /
    final cleanPath = elementPath.startsWith('/') ? elementPath : '/$elementPath';
    return 'epubcfi(/6/$spineNum$idPart!$cleanPath)';
  }

  /// Parses an EpubCFI string.
  /// Returns a Map containing:
  /// - `spineIndex` (int, 0-based)
  /// - `chapterId` (String)
  /// - `elementPath` (String, e.g. `/2/4/6/8`)
  static Map<String, dynamic>? parse(String cfi) {
    try {
      if (!cfi.startsWith('epubcfi(') || !cfi.endsWith(')')) return null;

      // Extract the inner content
      final content = cfi.substring(8, cfi.length - 1);
      final parts = content.split('!');
      if (parts.length < 2) return null;

      final spinePart = parts[0];
      final elementPath = parts.sublist(1).join('!'); // Re-join if there are multiple '!'

      // Parse spine index and ID: /6/4[chapter-2]
      final regExp = RegExp(r'\/6\/(\d+)(?:\[([^\]]+)\])?');
      final match = regExp.firstMatch(spinePart);
      if (match == null) return null;

      final spineNum = int.parse(match.group(1)!);
      final spineIndex = (spineNum ~/ 2) - 1;
      final chapterId = match.group(2) ?? '';

      return {
        'spineIndex': spineIndex,
        'chapterId': chapterId,
        'elementPath': elementPath,
      };
    } catch (e) {
      print('Error parsing CFI "$cfi": $e');
      return null;
    }
  }
}
