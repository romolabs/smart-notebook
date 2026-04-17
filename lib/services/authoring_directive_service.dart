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
    if (replacement == null) {
      return null;
    }

    final expandedText =
        nextText.substring(0, tokenStart) +
        replacement +
        trigger +
        nextText.substring(selectionOffset);
    final adjustedSelection =
        selectionOffset - token.length + replacement.length;

    return ShortcutExpansionResult(
      text: expandedText,
      selectionOffset: adjustedSelection,
    );
  }

  bool _isExpansionTrigger(String value) {
    return value == ' ' || value == '\n' || value == '\t';
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
