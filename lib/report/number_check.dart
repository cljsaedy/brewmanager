// the ai number check (rule 10)
// every number in the ai's text has to be a number that is in the facts, written as digits
// if one isnt, the report uses the template summary instead, so a wrong number never reaches the owner
//
// how it works:
// 1 pull every number out of the facts text (the json the ai got), these are the allowed numbers
// 2 pull every number out of the ai text, each one has to be in the allowed list
//   "1,700" and "1700" are the same number, the comma is only formatting
//   a minus or plus sign is ignored, "20 g less" and a gap of -20 both give 20
//   a rounded number is a mismatch: 1,000 in the text but 1,000.5 in the facts fails
// 3 a number written as a word ("two", "a dozen", "half") is a mismatch too,
//   the ai was told to always use digits, and words cant be checked against the facts
//   only exception: the word is in the facts too, like a note that says "two packs expired",
//   then quoting the note is fine

// the result: passed, or the numbers and words that didnt match
class NumberCheck {
  const NumberCheck(this.mismatches);

  final List<String> mismatches;

  bool get passed => mismatches.isEmpty;
}

// number words that make the check fail
// cardinals plus the common words for amounts, ordinals like "first" are left out since they also mean "the first count"
const List<String> numberWords = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
  'hundred',
  'thousand',
  'million',
  'dozen',
  'half',
  'quarter',
  'twice',
  'thrice',
];

// a number with commas between groups of 3 (1,700 or 12,500.5), or a plain one (1700, 2.96)
// the comma version is first so "1,700" is read as 1 number and not as 1 and 700
final RegExp _numberPattern = RegExp(
  r'\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?',
);

// \b = word edge, so "one" matches in "one pack" but not inside "done" or "phone"
final RegExp _wordPattern = RegExp(
  '\\b(${numberWords.join('|')})\\b',
  caseSensitive: false,
);

NumberCheck checkNumbers(String aiText, String factsText) {
  final allowed = numbersIn(factsText).toSet();
  final allowedWords = {
    for (final match in _wordPattern.allMatches(factsText))
      match.group(0)!.toLowerCase(),
  };

  final mismatches = <String>[];
  for (final match in _numberPattern.allMatches(aiText)) {
    final value = _parse(match.group(0)!);
    if (!allowed.contains(value)) mismatches.add(match.group(0)!);
  }
  for (final match in _wordPattern.allMatches(aiText)) {
    final word = match.group(0)!.toLowerCase();
    if (!allowedWords.contains(word)) mismatches.add(match.group(0)!);
  }
  return NumberCheck(mismatches);
}

// every number in a text as a value, commas taken out
List<double> numbersIn(String text) {
  return [
    for (final match in _numberPattern.allMatches(text))
      _parse(match.group(0)!),
  ];
}

// cut to 4 decimals so 0.1 + 0.2 style leftovers cant make 2 equal numbers look different
double _parse(String digits) {
  final value = double.parse(digits.replaceAll(',', ''));
  return (value * 10000).round() / 10000;
}
