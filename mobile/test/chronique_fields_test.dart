import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chronique/models/chronique_fields.dart';

void main() {
  test('9 non-whitespace characters are rejected', () {
    expect(ChroniqueFields.bodyError('abcdefghi'), isNotNull);
    expect(ChroniqueFields.bodyError('trop court'), 'Le texte doit contenir au moins 10 caractères');
  });

  test('10 non-whitespace characters are accepted', () {
    expect(ChroniqueFields.bodyError('abcdefghij'), isNull);
    expect(ChroniqueFields.nonWhitespaceLength('abcdefghij'), 10);
  });

  test('internal spaces do not count toward the minimum', () {
    const withSpaces = 'a a a a a a a a a a';
    expect(ChroniqueFields.trimmedBody(withSpaces), withSpaces);
    expect(ChroniqueFields.nonWhitespaceLength(withSpaces), 10);
    expect(ChroniqueFields.runeLength(withSpaces), 19);
    expect(ChroniqueFields.bodyError(withSpaces), isNull);
    expect(ChroniqueFields.bodyError('a a a a a a a a a'), isNotNull);
  });

  test('whitespace-only body is rejected', () {
    expect(ChroniqueFields.bodyError('   '), 'Le texte est obligatoire');
    expect(ChroniqueFields.bodyError('\n\t  '), 'Le texte est obligatoire');
  });

  test('1000 characters including spaces are accepted', () {
    final body = 'a' * 990 + ' ' * 10;
    expect(ChroniqueFields.runeLength(body), 1000);
    expect(ChroniqueFields.nonWhitespaceLength(body), 990);
    expect(ChroniqueFields.bodyError(body), isNull);
  });

  test('1001 characters are rejected', () {
    expect(ChroniqueFields.bodyError('a' * 1001), 'Le texte est trop long');
  });

  test('accents and unicode code points count as one character each', () {
    expect(ChroniqueFields.bodyError('éééééééééé'), isNull);
    expect(ChroniqueFields.runeLength('éééééééééé'), 10);
    expect(ChroniqueFields.bodyError('ééééééééé'), isNotNull);
    expect(ChroniqueFields.bodyError('🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂'), isNull);
    expect(ChroniqueFields.runeLength('🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂'), 10);
  });

  test('trim keeps internal spaces and is used for create and edit', () {
    const raw = '  hello world  ';
    expect(ChroniqueFields.trimmedBody(raw), 'hello world');
    expect(ChroniqueFields.bodyError(raw), isNull);
    expect(ChroniqueFields.canPublishBody(raw), isTrue);
  });
}
