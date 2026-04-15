import '../models/notebook_models.dart';
import '../services/mock_enhancement_engine.dart';

List<NotebookNote> buildSeedNotes(MockEnhancementEngine engine) {
  final now = DateTime.now();
  final toggles = const ProcessorToggles(
    spelling: true,
    formatting: true,
    clarity: true,
    verification: true,
  );

  final seeds = [
    (
      id: '1',
      title: 'AI notebook product direction',
      category: 'Strategy',
      updatedAt: now.subtract(const Duration(minutes: 8)),
      rawContent: '''
dual panel notebook
left side raw thoughts right side ai enhanced
need to make trust the main thing
according to research says nobody combines local models + split view + specialist agents
launch desktop first maybe mac and windows
''',
    ),
    (
      id: '2',
      title: 'Meeting notes with designer',
      category: 'Meeting',
      updatedAt: now.subtract(const Duration(hours: 3)),
      rawContent: '''
talked about onboarding
- first minute needs wow moment
- keep raw pane calm
- enhanced pane can feel more editorial
maybe ship beta to 250 users in 2027
''',
    ),
    (
      id: '3',
      title: 'Lecture scraps',
      category: 'Study',
      updatedAt: now.subtract(const Duration(days: 1)),
      rawContent: '''
teh network has 1200 samples
need to double check if professor said 0.05 or 0.5 learning rate
recieve feedback from study group tomorrow
''',
    ),
  ];

  return seeds.map((seed) {
    final snapshot = engine.processSync(
      EnhancementRequest(
        rawContent: seed.rawContent,
        modelMode: ModelMode.localFast,
        toggles: toggles,
      ),
    );
    return NotebookNote(
      id: seed.id,
      title: seed.title,
      category: seed.category,
      createdAt: seed.updatedAt,
      updatedAt: seed.updatedAt,
      rawContent: seed.rawContent,
      versions: [
        NotebookVersion(
          id: 'seed-${seed.id}',
          createdAt: seed.updatedAt,
          rawContent: seed.rawContent,
          enhancedContent: snapshot.enhancedContent,
          modelMode: ModelMode.localFast,
        ),
      ],
    );
  }).toList();
}
