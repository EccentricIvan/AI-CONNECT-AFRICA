/// Programming Learn subjects and the 1.5B coder brain.
///
/// One model (Qwen2.5-Coder-1.5B) tutors everything; programming subjects just
/// get the programming contract. AfriSLM does the language hops.
library;

const kProgrammingSubjectIds = {
  'programming',
  'web_development',
  'app_development',
};

const kProgrammingSubjectNames = {
  'Programming',
  'Web Development',
  'App Development',
};

const kProgrammingTopicIds = {
  'programming',
  'web_development',
  'app_development',
};

/// Words that mean this turn is coding — not biology "cells" or school "class".
const kProgrammingKeywords = [
  'python',
  'javascript',
  'html',
  'css',
  'flutter',
  'django',
  'flask',
  'react',
  'website',
  'webpage',
  'web page',
  'web dev',
  'frontend',
  'front-end',
  'backend',
  'back-end',
  'flexbox',
  'mobile app',
  'android app',
  'ios app',
  'source code',
  'syntax error',
  'for loop',
  'while loop',
  'if statement',
  'print(',
  'def ',
  'import ',
  'console.log',
  'algorithm',
  'debug',
  'debugging',
  'software',
  'script',
  'coding',
  'programmer',
  'compiler',
  'indent',
  'variable',
  'function',
];

bool isProgrammingSubjectId(String? id) {
  if (id == null || id.isEmpty) return false;
  return kProgrammingSubjectIds.contains(id.trim().toLowerCase());
}

bool isProgrammingSubjectName(String? name) {
  if (name == null || name.isEmpty) return false;
  return kProgrammingSubjectNames.contains(name.trim());
}

bool isProgrammingTopicId(String? topic) {
  if (topic == null || topic.isEmpty) return false;
  return kProgrammingTopicIds.contains(topic.trim().toLowerCase());
}

/// True when the student is asking to code, build a site/app, or learn Python.
bool looksLikeProgramming(String text) {
  final lower = text.toLowerCase();
  if (lower.trim().isEmpty) return false;
  for (final keyword in kProgrammingKeywords) {
    if (lower.contains(keyword)) return true;
  }
  if (RegExp(r'\bpython\b').hasMatch(lower)) return true;
  if (RegExp(r'\bhtml\b').hasMatch(lower)) return true;
  if (RegExp(r'\bcss\b').hasMatch(lower)) return true;
  if (RegExp(r'\bcode\b').hasMatch(lower)) return true;
  if (RegExp(r'\bprogram(?:s|ming)?\b').hasMatch(lower)) return true;
  if (RegExp(r'```').hasMatch(text)) return true;
  return false;
}

/// First student turn when they open a curriculum coding lesson in chat.
String codingLessonChatOpener(String lessonTitle) {
  final title = lessonTitle.trim();
  if (title.isEmpty) {
    return 'I want to learn programming from the curriculum. '
        'Teach it like a chat: start with the idea, then one tiny code example I can try.';
  }
  return 'I want to learn "$title" from the curriculum. '
      'Teach it like a chat: start with the idea in everyday language, '
      'then one tiny code example I can try.';
}

const kCodingChipTryExample = 'Try that example';
const kCodingChipCheckCode = 'Check the code I will paste next';
const kCodingChipPractice = 'Give me a practice from this lesson';
const kCodingChipNext = 'What should I learn next from this lesson?';
