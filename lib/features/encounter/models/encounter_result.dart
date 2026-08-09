enum EncounterOutcome { win, escaped, dead }

class EncounterResult {
  final EncounterOutcome outcome;

  const EncounterResult({required this.outcome});
}
