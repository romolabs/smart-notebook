import '../models/notebook_models.dart';

class ProposalMerger {
  const ProposalMerger();

  String merge({
    required ChampionDraft champion,
    required List<LineEditProposal> acceptedLineEdits,
  }) {
    if (acceptedLineEdits.isEmpty) {
      return champion.text;
    }

    final replacements = {
      for (final edit in acceptedLineEdits)
        edit.lineIndex: edit.replacement.trim(),
    };

    final renderedBlocks = champion.structure.blocks
        .map((block) {
          final lines = block.lines
              .map((line) {
                return replacements[line.index] ??
                    champion.renderedLinesBySourceIndex[line.index] ??
                    line.sourceLine.trimRight();
              })
              .toList(growable: false);
          return lines.join('\n');
        })
        .toList(growable: false);

    return renderedBlocks.join('\n\n').trim();
  }
}
