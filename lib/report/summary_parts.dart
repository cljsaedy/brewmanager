// the owner's summary in 5 parts (rule 10), the ai and the template both fill these
// each part is a short plain paragraph, or empty text when it has nothing to say
// the email shows each part under its own header and hides the empty ones
class SummaryParts {
  const SummaryParts({
    required this.overview,
    required this.gaps,
    required this.restock,
    required this.containers,
    required this.fine,
  });

  // what happened today, like how many menu items were ordered (header "Today")
  final String overview;
  // every number item whose gap isnt 0, with its note, biggest first (header "Gaps")
  final String gaps;
  // items at or below their low-stock level
  final String restock;
  // every container finished: what it held vs what the orders explain, no judging
  final String containers;
  // the closing line "Everything else matched." when there are no gaps, no header
  final String fine;

  // the json field names, the same ones the ai is told to fill
  static const List<String> keys = [
    'overview',
    'gaps',
    'restock',
    'containers',
    'fine',
  ];

  // the header the email shows above each part, fine has none
  static const Map<String, String> headers = {
    'overview': 'Today',
    'gaps': 'Gaps',
    'restock': 'Restock',
    'containers': 'Containers finished',
  };

  // the parts by their json name, in the order the email shows them
  Map<String, String> get byKey => {
    'overview': overview,
    'gaps': gaps,
    'restock': restock,
    'containers': containers,
    'fine': fine,
  };

  // reads the ai's json answer, throws FormatException when it isnt the right shape
  // every field must be there and be text, extra spaces around it are taken off
  factory SummaryParts.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('the answer is not an object');
    }
    String field(String key) {
      final value = json[key];
      if (value is! String) throw FormatException('"$key" is missing');
      return value.trim();
    }

    return SummaryParts(
      overview: field('overview'),
      gaps: field('gaps'),
      restock: field('restock'),
      containers: field('containers'),
      fine: field('fine'),
    );
  }
}
