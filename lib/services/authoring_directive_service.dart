class ShortcutExpansionResult {
  const ShortcutExpansionResult({
    required this.text,
    required this.selectionOffset,
  });

  final String text;
  final int selectionOffset;
}

class AuthoringDirectiveService {
  const AuthoringDirectiveService();

  static const String mathDirectiveStart = '/math';
  static const String directiveEnd = '/end';

  static const Map<String, String> _symbolShortcuts = {
    '/alpha': 'α',
    '/beta': 'β',
    '/gamma': 'γ',
    '/delta': 'δ',
    '/theta': 'θ',
    '/lambda': 'λ',
    '/pi': 'π',
    '/sigma': 'σ',
    '/Sigma': 'Σ',
    '/sum': '∑',
    '/int': '∫',
    '/sqrt': '√',
    '/inf': '∞',
    '/neq': '≠',
    '/leq': '≤',
    '/geq': '≥',
    '/approx': '≈',
    '/pm': '±',
    '/times': '×',
    '/div': '÷',
    '/partial': '∂',
    '/grad': '∇',
  };
  static const Map<String, String> _lineCommands = {
    '/h1': '# ',
    '/bullet': '- ',
    '/check': '- [ ] ',
  };

  ShortcutExpansionResult? expandTrailingShortcut({
    required String previousText,
    required String nextText,
    required int selectionOffset,
  }) {
    if (nextText == previousText) {
      return null;
    }
    if (selectionOffset <= 0 || selectionOffset > nextText.length) {
      return null;
    }

    final trigger = nextText[selectionOffset - 1];
    if (!_isExpansionTrigger(trigger)) {
      return null;
    }

    final tokenEnd = selectionOffset - 1;
    final tokenStart = _tokenStart(nextText, tokenEnd);
    if (tokenStart >= tokenEnd) {
      return null;
    }

    final token = nextText.substring(tokenStart, tokenEnd);
    final replacement = _symbolShortcuts[token];
    if (replacement != null) {
      return _replaceToken(
        nextText: nextText,
        tokenStart: tokenStart,
        tokenEnd: tokenEnd,
        selectionOffset: selectionOffset,
        replacement: '$replacement$trigger',
      );
    }

    final lineCommand = _lineCommands[token];
    if (lineCommand != null && _isLineCommandTrigger(trigger)) {
      return _replaceToken(
        nextText: nextText,
        tokenStart: tokenStart,
        tokenEnd: tokenEnd,
        selectionOffset: selectionOffset,
        replacement: lineCommand,
      );
    }

    if (token == mathDirectiveStart && _isMathBlockTrigger(trigger)) {
      return _replaceToken(
        nextText: nextText,
        tokenStart: tokenStart,
        tokenEnd: tokenEnd,
        selectionOffset: selectionOffset,
        replacement: _mathBlockSnippet(),
        caretOffset: tokenStart + '$mathDirectiveStart\n'.length,
      );
    }

    return null;
  }

  ShortcutExpansionResult insertMathBlock({
    required String originalText,
    required int selectionStart,
    required int selectionEnd,
  }) {
    final start = selectionStart < 0 ? originalText.length : selectionStart;
    final end = selectionEnd < 0 ? originalText.length : selectionEnd;
    final selectedText = originalText.substring(start, end);
    final snippet = _mathBlockSnippet(body: selectedText);
    final caretOffset =
        start + '$mathDirectiveStart\n'.length + selectedText.length;
    final updatedText = originalText.replaceRange(start, end, snippet);

    return ShortcutExpansionResult(
      text: updatedText,
      selectionOffset: caretOffset,
    );
  }

  bool _isExpansionTrigger(String value) {
    return value == ' ' || value == '\n' || value == '\t';
  }

  bool _isLineCommandTrigger(String value) {
    return value == ' ';
  }

  bool _isMathBlockTrigger(String value) {
    return value == ' ' || value == '\n';
  }

  ShortcutExpansionResult _replaceToken({
    required String nextText,
    required int tokenStart,
    required int tokenEnd,
    required int selectionOffset,
    required String replacement,
    int? caretOffset,
  }) {
    final expandedText =
        nextText.substring(0, tokenStart) +
        replacement +
        nextText.substring(selectionOffset);
    final adjustedSelection = caretOffset ?? tokenStart + replacement.length;

    return ShortcutExpansionResult(
      text: expandedText,
      selectionOffset: adjustedSelection,
    );
  }

  String _mathBlockSnippet({String body = ''}) {
    if (body.isEmpty) {
      return '$mathDirectiveStart\n\n$directiveEnd';
    }

    final normalizedBody = body.endsWith('\n') ? body : '$body\n';
    return '$mathDirectiveStart\n$normalizedBody$directiveEnd';
  }

  int _tokenStart(String text, int tokenEnd) {
    var cursor = tokenEnd - 1;
    while (cursor >= 0) {
      final char = text[cursor];
      if (char == ' ' || char == '\n' || char == '\t') {
        return cursor + 1;
      }
      cursor--;
    }
    return 0;
  }
}
