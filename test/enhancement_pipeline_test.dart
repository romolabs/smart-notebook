import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/models/notebook_models.dart';
import 'package:smart_notebook/services/acceptance_gate.dart';
import 'package:smart_notebook/services/deterministic_formatter.dart';
import 'package:smart_notebook/services/note_parser.dart';

void main() {
  const parser = NoteParser();
  const formatter = DeterministicFormatter();
  const gate = AcceptanceGate();
  const toggles = ProcessorToggles(
    spelling: true,
    formatting: true,
    clarity: true,
    verification: true,
  );

  test(
    'deterministic formatter preserves structure without inventing sections',
    () {
      final structure = parser.parse('''
meeting notes
- first draft
* second draft
- [x] ship beta
2) email team
''');

      final champion = formatter.buildChampionDraft(
        structure,
        toggles: toggles,
      );

      expect(champion.text, isNot(contains('# Enhanced Note')));
      expect(champion.text, contains('- first draft'));
      expect(champion.text, contains('- second draft'));
      expect(champion.text, contains('- [x] ship beta'));
      expect(champion.text, contains('2. email team'));
    },
  );

  test('acceptance gate rejects structure-breaking formatter drafts', () {
    final champion = formatter.buildChampionDraft(
      parser.parse('''
Title: roadmap
1) ship beta
2) email team
'''),
      toggles: toggles,
    );

    final report = gate.evaluateFormatterCandidate(
      champion: champion,
      candidateText: '''
# Enhanced Note
- ship beta soon
''',
    );

    expect(report.accepted, isFalse);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll([
        'block_structure_changed',
        'line_structure_changed',
        'ordered_count_changed',
        'protected_tokens_missing',
      ]),
    );
  });
}
