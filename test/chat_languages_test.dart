import 'package:ai_connect_africa/ai_core/translate/chat_languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary chat languages include East Africa plus Somali and Lingala', () {
    expect(kPrimaryChatLanguages, ['en', 'lg', 'sw', 'rw', 'so', 'ln']);
    expect(chatLanguages.map((l) => l.code), kPrimaryChatLanguages);
  });

  test('coerceChatLanguage maps unsupported codes to English', () {
    expect(coerceChatLanguage('lg'), 'lg');
    expect(coerceChatLanguage('yo'), 'yo');
    expect(coerceChatLanguage('zu'), 'zu');
    expect(coerceChatLanguage('fr'), 'en');
  });

  test('chatTranslatePromptName is distinct per language', () {
    expect(chatTranslatePromptName('lg'), 'Luganda');
    expect(chatTranslatePromptName('rw'), 'Kinyarwanda');
    expect(chatTranslatePromptName('sw'), 'Swahili');
    expect(chatTranslatePromptName('so'), 'Somali');
    expect(chatTranslatePromptName('ln'), 'Lingala');
  });
}
