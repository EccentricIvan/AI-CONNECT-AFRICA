/// Deterministic school-math solver (MathGPT-style).
///
/// Qwen3-0.6B predicts words; it does not compute. When a problem matches
/// a known school pattern we calculate in Dart and fill named steps so the
/// learner never sees invented sums like 250+100=350.
library;

String? trySchoolMathPlan(String question) =>
    solveSchoolMath(question)?.fullPlan;

/// `5000g` → `5000 g` so unit regexes that need a word boundary still fire.
String _splitGluedUnits(String q) {
  return q.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)(kg|cm|mm|km|ml|g|m|l)\b'),
    (m) => '${m[1]} ${m[2]}',
  );
}

/// True when [query] is algebra/arithmetic, not a prose lesson lookup.
///
/// Curriculum matching is keyword overlap. Mixed local-language math
/// ("Shaka agaciro ka x … 4x - 15 = 12x") used to pick unrelated lessons
/// such as arts "Figurative Painting". Skip the lookup entirely.
bool queryLooksLikeMath(String query) {
  final t = query.trim();
  if (t.isEmpty) return false;
  if (solveSchoolMath(t) != null) return true;
  if (t.contains(r'$')) return true;
  return RegExp(
    r'(?:\d\s*[a-zA-Z]|\b[a-zA-Z]\b)\s*[+\-*/=×÷^]|'
    r'[+\-*/=×÷^]\s*(?:\d|\b[a-zA-Z]\b)|'
    r'\d+\s*[+\-*/=×÷^]\s*\d',
  ).hasMatch(t);
}

SchoolMathSolution? solveSchoolMath(String question) {
  final q = _splitGluedUnits(
    question.trim().toLowerCase().replaceAll(',', ''),
  );
  if (q.isEmpty) return null;
  // Equations like `2x+3=11` survive any wrapping language ("Nnyonnyola
  // ekibonerezo kino: 2x + 3 = 11"). Parse them first so chat can skip
  // AfriSLM inbound and still show a worked solution.
  if (_hasLinearEquation(q)) return _parseLinear(q);
  return _parseConversion(q) ??
      _parsePercent(q) ??
      _parseFractionOf(q) ??
      _parseLinear(q) ??
      _parseRectangle(q) ??
      _parseArithmetic(q);
}

bool _hasLinearEquation(String q) {
  final compact = q.replaceAll(' ', '');
  return RegExp(
        r'(?:[+-]?\d*(?:\.\d+)?)[x×](?:[+-]\d+(?:\.\d+)?)?=[+-]?\d',
      ).hasMatch(compact) ||
      RegExp(r'x[+-]\d+(?:\.\d+)?=[+-]?\d').hasMatch(compact);
}

class MathStep {
  const MathStep({
    required this.title,
    required this.why,
    this.formula,
    this.calc,
  });

  final String title;
  final String why;
  final String? formula;
  final String? calc;

  MathStep copyWith({String? title, String? why}) {
    return MathStep(
      title: title ?? this.title,
      why: why ?? this.why,
      formula: formula,
      calc: calc,
    );
  }
}

class SchoolMathSolution {
  const SchoolMathSolution({
    required this.steps,
    required this.answer,
    required this.hint,
    required this.practiceQuestion,
    this.numericAnswer,
  });

  final List<MathStep> steps;
  final String answer;
  final String hint;
  final String practiceQuestion;
  final double? numericAnswer;

  String get fullPlan {
    final b = StringBuffer();
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      b.writeln('Step ${i + 1}: ${s.title}');
      b.writeln(s.why);
      if (s.formula != null && s.formula!.isNotEmpty) {
        b.writeln();
        b.writeln(s.formula);
      }
      if (s.calc != null && s.calc!.isNotEmpty) {
        b.writeln();
        b.writeln(s.calc);
      }
      if (i < steps.length - 1) b.writeln();
    }
    b.writeln();
    b.write('Answer: $answer');
    return b.toString().trim();
  }

  String get hintMessage =>
      '$hint\n\nTry the calculation, then tell me your answer — or ask me to show the full steps.';

  SchoolMathSolution copyWith({
    List<MathStep>? steps,
    String? hint,
    String? practiceQuestion,
  }) {
    return SchoolMathSolution(
      steps: steps ?? this.steps,
      answer: answer,
      hint: hint ?? this.hint,
      practiceQuestion: practiceQuestion ?? this.practiceQuestion,
      numericAnswer: numericAnswer,
    );
  }
}

String fmtNum(double n) {
  if (n == n.roundToDouble()) return n.round().toString();
  var s = n.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

bool nearlyEqual(double a, double b, {double rel = 1e-6}) {
  final scale = a.abs() > b.abs() ? a.abs() : b.abs();
  final tol = scale < 1 ? 1e-6 : scale * rel;
  return (a - b).abs() <= (tol < 0.01 ? 0.01 : tol);
}

double? extractNumericAttempt(String message) {
  final t = message.trim().toLowerCase();
  final m = RegExp(
    r"^(?:is it|answer(?: is)?|i think|maybe|it(?:'s| is)?)\s+"
    r'(-?\d+(?:\.\d+)?)\s*[a-z%]*\.?$',
  ).firstMatch(t);
  if (m != null) return double.tryParse(m.group(1)!);
  if (RegExp(r'^-?\d+(?:\.\d+)?\s*[a-z%]*\.?$').hasMatch(t)) {
    return double.tryParse(RegExp(r'-?\d+(?:\.\d+)?').firstMatch(t)!.group(0)!);
  }
  return null;
}

String _coachNorm(String message) =>
    message.trim().toLowerCase().replaceAll(RegExp(r'[?.!]'), '');

bool wantsMathHint(String message) {
  final t = _coachNorm(message);
  return RegExp(
    r'^(please\s+)?((give me |i (need |want )?)?(a )?hint|a clue|nudge)$',
  ).hasMatch(t);
}

bool wantsFullMathSteps(String message) {
  final t = _coachNorm(message);
  return RegExp(
    r'^(please\s+)?('
    r'show( me)?( the)?( full)? steps|'
    r'show( me)? the (full )?solution|'
    r'full solution|'
    r'show( me)? the (answer|work|working)|'
    r'explain the steps|'
    r"i don'?t know|idk|"
    r'give me the answer'
    r')$',
  ).hasMatch(t);
}

/// True when the message is a hint / show-steps / bare numeric try — not a new question.
bool isMathCoachingFollowUp(String message) {
  if (wantsMathHint(message) || wantsFullMathSteps(message)) return true;
  return extractNumericAttempt(message) != null &&
      solveSchoolMath(message) == null;
}

double _variant(double v) {
  if (v == v.roundToDouble()) {
    final n = v.round();
    if (n <= 0) return 2;
    if (n % 100 == 0) return (n + 100).toDouble();
    if (n % 10 == 0) return (n + 50).toDouble();
    return (n + 4).toDouble();
  }
  return double.parse((v + 1).toStringAsFixed(2));
}

// ── Conversions ──────────────────────────────────────────────────────────────

class _Unit {
  const _Unit(this.id, this.name);
  final String id;
  final String name;
}

class _Rule {
  const _Rule(this.factor, this.divide, this.identity);
  final double factor;
  final bool divide;
  final String identity;
}

_Unit? _findUnit(String text, {int afterIndex = 0, String? skip}) {
  final slice = afterIndex == 0 ? text : text.substring(afterIndex);
  const units = <_Unit>[
    _Unit('cm', 'centimeters'),
    _Unit('mm', 'millimeters'),
    _Unit('km', 'kilometers'),
    _Unit('ml', 'millilitres'),
    _Unit('kg', 'kilograms'),
    _Unit('m', 'meters'),
    _Unit('g', 'grams'),
    _Unit('l', 'litres'),
  ];
  final patterns = <String, String>{
    'centimet': 'cm',
    'centimeter': 'cm',
    'millimet': 'mm',
    'millimeter': 'mm',
    'kilomet': 'km',
    'kilometer': 'km',
    'metres': 'm',
    'meters': 'm',
    'metre': 'm',
    'meter': 'm',
    'kilogram': 'kg',
    'grams': 'g',
    'gram': 'g',
    'litres': 'l',
    'liters': 'l',
    'litre': 'l',
    'liter': 'l',
  };
  for (final u in units) {
    if (skip == u.id) continue;
    if (RegExp('\\b${u.id}\\b').hasMatch(slice)) return u;
  }
  for (final e in patterns.entries) {
    if (skip == e.value) continue;
    if (slice.contains(e.key)) {
      return units.firstWhere((u) => u.id == e.value);
    }
  }
  return null;
}

_Rule? _rule(String from, String to) {
  const table = <String, _Rule>{
    'cm>m': _Rule(100, true, '1 m = 100 cm'),
    'm>cm': _Rule(100, false, '1 m = 100 cm'),
    'mm>cm': _Rule(10, true, '1 cm = 10 mm'),
    'cm>mm': _Rule(10, false, '1 cm = 10 mm'),
    'mm>m': _Rule(1000, true, '1 m = 1000 mm'),
    'm>mm': _Rule(1000, false, '1 m = 1000 mm'),
    'm>km': _Rule(1000, true, '1 km = 1000 m'),
    'km>m': _Rule(1000, false, '1 km = 1000 m'),
    'g>kg': _Rule(1000, true, '1 kg = 1000 g'),
    'kg>g': _Rule(1000, false, '1 kg = 1000 g'),
    'ml>l': _Rule(1000, true, '1 l = 1000 ml'),
    'l>ml': _Rule(1000, false, '1 l = 1000 ml'),
  };
  return table['$from>$to'];
}

SchoolMathSolution? _parseConversion(String q) {
  final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(q);
  if (numMatch == null) return null;
  final value = double.tryParse(numMatch.group(1)!);
  if (value == null) return null;

  final from = _findUnit(q);
  if (from == null) return null;

  _Unit? to;
  final howMany = RegExp(r'how many\s+([a-z]+)').firstMatch(q);
  if (howMany != null) {
    to = _findUnit(howMany.group(1)!);
  }
  final toAnchor = RegExp(r'\b(?:to|into)\b').firstMatch(q);
  if (to == null && toAnchor != null) {
    to = _findUnit(q.substring(toAnchor.end));
  }
  to ??= _findUnit(q, skip: from.id);
  if (to == null || to.id == from.id) return null;

  final rule = _rule(from.id, to.id);
  if (rule == null) return null;

  final result = rule.divide ? value / rule.factor : value * rule.factor;
  final v = fmtNum(value);
  final r = fmtNum(result);
  final f = fmtNum(rule.factor);
  final op = rule.divide ? '÷' : '×';
  final verb = rule.divide ? 'divide' : 'multiply';
  final formula = rule.divide
      ? '${to.name} = ${from.name} / $f'
      : '${to.name} = ${from.name} × $f';

  return SchoolMathSolution(
    numericAnswer: result,
    answer: '$r ${to.id}',
    hint:
        '${rule.identity}. ${from.name} → ${to.name}: $verb by $f. Do not add the factor to the quantity.',
    practiceQuestion: 'Convert ${fmtNum(_variant(value))} ${from.id} to ${to.name}.',
    steps: [
      MathStep(
        title: 'Identify the conversion factor',
        why:
            'Determine the standard metric ratio between ${from.name} and ${to.name}.',
        formula: rule.identity,
      ),
      MathStep(
        title: 'Set up the ${rule.divide ? 'division' : 'multiplication'} formula',
        why:
            'To change ${from.name} into ${to.name}, $verb the quantity by $f.',
        formula: formula,
      ),
      MathStep(
        title: 'Substitute the value',
        why: 'Plug $v ${from.id} into the conversion formula.',
        formula: '${to.name} = $v ${rule.divide ? '/ $f' : '× $f'}',
      ),
      MathStep(
        title: 'Execute the arithmetic',
        why: 'Only this calculation belongs to the method — never add the factor.',
        calc: '$v $op $f = $r',
      ),
      MathStep(
        title: 'Attach the target unit',
        why: 'State the finalized measurement with its correct unit.',
        calc: '$v ${from.id} = $r ${to.id}',
      ),
    ],
  );
}

// ── Percent ──────────────────────────────────────────────────────────────────

SchoolMathSolution? _parsePercent(String q) {
  final of = RegExp(r'(\d+(?:\.\d+)?)\s*%\s*(?:of|×|x|\*)\s*(\d+(?:\.\d+)?)')
      .firstMatch(q);
  if (of != null) {
    final p = double.parse(of.group(1)!);
    final base = double.parse(of.group(2)!);
    final result = p / 100 * base;
    final r = fmtNum(result);
    return SchoolMathSolution(
      numericAnswer: result,
      answer: r,
      hint: 'Percent means per hundred. $p% of ${fmtNum(base)} is ($p ÷ 100) × ${fmtNum(base)}.',
      practiceQuestion: 'What is ${fmtNum(_variant(p))}% of ${fmtNum(base)}?',
      steps: [
        MathStep(
          title: 'Write percent as a fraction of 100',
          why: 'n% means n per hundred.',
          formula: '$p% = $p / 100',
        ),
        const MathStep(
          title: 'Set up the "percent of" formula',
          why: 'Of means multiply.',
          formula: 'value = (percent / 100) × base',
        ),
        MathStep(
          title: 'Substitute',
          why: 'Put in $p and ${fmtNum(base)}.',
          formula: 'value = ($p / 100) × ${fmtNum(base)}',
        ),
        MathStep(
          title: 'Execute the arithmetic',
          why: 'First form the decimal, then multiply.',
          calc: '${fmtNum(p / 100)} × ${fmtNum(base)} = $r',
        ),
        MathStep(
          title: 'State the result',
          why: 'This quantity has the same unit as the base (if any).',
          calc: '$p% of ${fmtNum(base)} = $r',
        ),
      ],
    );
  }

  final change = RegExp(
    r'(increase|decrease|reduce)\s+(\d+(?:\.\d+)?)\s+by\s+(\d+(?:\.\d+)?)\s*%',
  ).firstMatch(q);
  if (change != null) {
    final up = change.group(1) == 'increase';
    final base = double.parse(change.group(2)!);
    final p = double.parse(change.group(3)!);
    final delta = p / 100 * base;
    final result = up ? base + delta : base - delta;
    final r = fmtNum(result);
    final sign = up ? '+' : '−';
    return SchoolMathSolution(
      numericAnswer: result,
      answer: r,
      hint:
          'Find $p% of ${fmtNum(base)} first, then ${up ? 'add it to' : 'subtract it from'} ${fmtNum(base)}.',
      practiceQuestion:
          '${up ? 'Increase' : 'Decrease'} ${fmtNum(_variant(base))} by ${fmtNum(p)}%.',
      steps: [
        MathStep(
          title: 'Find the percentage amount',
          why: 'The change is $p% of the original value.',
          formula: 'change = ($p / 100) × ${fmtNum(base)}',
          calc: 'change = ${fmtNum(delta)}',
        ),
        MathStep(
          title: up ? 'Add the change' : 'Subtract the change',
          why: up ? 'An increase adds the change.' : 'A decrease subtracts the change.',
          formula: 'new value = ${fmtNum(base)} $sign ${fmtNum(delta)}',
        ),
        MathStep(
          title: 'Execute the arithmetic',
          why: 'Combine the original amount and the change.',
          calc: '${fmtNum(base)} $sign ${fmtNum(delta)} = $r',
        ),
        MathStep(
          title: 'State the result',
          why: 'The new amount after the ${up ? 'increase' : 'decrease'}.',
          calc: 'Answer = $r',
        ),
      ],
    );
  }
  return null;
}

// ── Fraction of ──────────────────────────────────────────────────────────────

SchoolMathSolution? _parseFractionOf(String q) {
  // "of" plus the short connectors AfriSLM languages actually use
  // ("3/4 ku 80", "3/4 ya 80") so the solver does not wait on inbound.
  final m = RegExp(
    r'(\d+)\s*/\s*(\d+)\s+(?:of|ku|ya|ye|za|wa|ka)\s+(\d+(?:\.\d+)?)',
  ).firstMatch(q);
  if (m == null) return null;
  final nume = double.parse(m.group(1)!);
  final den = double.parse(m.group(2)!);
  if (den == 0) return null;
  final base = double.parse(m.group(3)!);
  final result = nume / den * base;
  final r = fmtNum(result);
  return SchoolMathSolution(
    numericAnswer: result,
    answer: r,
    hint: '${fmtNum(nume)}/${fmtNum(den)} of ${fmtNum(base)} means (${fmtNum(nume)} ÷ ${fmtNum(den)}) × ${fmtNum(base)}.',
    practiceQuestion: 'What is ${fmtNum(nume)}/${fmtNum(den)} of ${fmtNum(_variant(base))}?',
    steps: [
      MathStep(
        title: 'Read the fraction as a multiplier',
        why: '"Of" means multiply by the fraction.',
        formula: 'value = ($nume / $den) × ${fmtNum(base)}',
      ),
      MathStep(
        title: 'Substitute',
        why: 'Keep numerator, denominator, and the whole amount.',
        formula: 'value = ${fmtNum(nume)} / ${fmtNum(den)} × ${fmtNum(base)}',
      ),
      MathStep(
        title: 'Execute the arithmetic',
        why: 'Divide first, then multiply — or multiply then divide by the denominator.',
        calc: '${fmtNum(nume / den)} × ${fmtNum(base)} = $r',
      ),
      MathStep(
        title: 'State the result',
        why: 'The result is a share of the original amount.',
        calc: '${fmtNum(nume)}/${fmtNum(den)} of ${fmtNum(base)} = $r',
      ),
    ],
  );
}

// ── Linear ax + b = c ────────────────────────────────────────────────────────

SchoolMathSolution? _parseLinear(String q) {
  q = q.replaceFirst(RegExp(r'solve(?:\s+for\s+x)?[:\s]*'), '');
  final compact = q.replaceAll(' ', '');
  final n = RegExp(
    r'([+-]?\d*(?:\.\d+)?)[x×]'
    r'(?:([+-])(\d+(?:\.\d+)?))?'
    r'='
    r'([+-]?\d+(?:\.\d+)?)',
  ).firstMatch(compact);
  if (n == null) {
    final simple = RegExp(
      r'(?:solve[:\s]+)?\s*([+-]?\d*(?:\.\d+)?)\s*[x×]\s*=\s*([+-]?\d+(?:\.\d+)?)',
    ).firstMatch(q);
    if (simple != null) {
      return _linear(simple.group(1)!, '', '0', simple.group(2)!);
    }
    final xAlone = RegExp(
      r'(?:solve[:\s]+)?\s*x\s*([+-])\s*(\d+(?:\.\d+)?)\s*=\s*([+-]?\d+(?:\.\d+)?)',
    ).firstMatch(q);
    if (xAlone != null) {
      return _linear('1', xAlone.group(1)!, xAlone.group(2)!, xAlone.group(3)!);
    }
    return null;
  }
  return _linear(n.group(1)!, n.group(2) ?? '', n.group(3) ?? '0', n.group(4)!);
}

SchoolMathSolution? _linear(String aRaw, String sign, String bRaw, String cRaw) {
  double a;
  if (aRaw.isEmpty || aRaw == '+') {
    a = 1;
  } else if (aRaw == '-') {
    a = -1;
  } else {
    a = double.tryParse(aRaw) ?? 1;
  }
  if (a == 0) return null;
  var b = double.tryParse(bRaw) ?? 0;
  if (sign == '-') b = -b;
  if (sign.isEmpty) b = 0;
  final c = double.tryParse(cRaw);
  if (c == null) return null;

  final rhs = c - b;
  final x = rhs / a;
  final r = fmtNum(x);
  final aS = fmtNum(a);
  final bS = fmtNum(b.abs());
  final bTerm = b == 0 ? '' : (b > 0 ? ' + $bS' : ' − $bS');
  final undo = b == 0
      ? 'No constant to move.'
      : (b > 0
          ? 'Subtract $bS from both sides.'
          : 'Add $bS to both sides.');

  return SchoolMathSolution(
    numericAnswer: x,
    answer: 'x = $r',
    hint: 'Undo the constant first ($undo) then divide by $aS to isolate x.',
    practiceQuestion: b == 0
        ? 'Solve ${fmtNum(a)}x = ${fmtNum(_variant(c))}.'
        : 'Solve ${fmtNum(a)}x${b > 0 ? ' +' : ' -'} ${fmtNum(_variant(b.abs()))} = ${fmtNum(_variant(c))}.',
    steps: [
      MathStep(
        title: 'Write the equation',
        why: 'Identify the coefficient of x and the constant term.',
        formula: '${aS}x$bTerm = ${fmtNum(c)}',
      ),
      MathStep(
        title: 'Undo the constant',
        why: undo,
        formula: b == 0
            ? '${aS}x = ${fmtNum(c)}'
            : '${aS}x = ${fmtNum(c)} ${b > 0 ? '−' : '+'} $bS',
        calc: b == 0 ? null : '${aS}x = ${fmtNum(rhs)}',
      ),
      MathStep(
        title: 'Divide to isolate x',
        why: 'Divide both sides by $aS.',
        formula: 'x = ${fmtNum(rhs)} / $aS',
      ),
      MathStep(
        title: 'Execute the arithmetic',
        why: 'This is the only division the method needs.',
        calc: 'x = $r',
      ),
      MathStep(
        title: 'State the solution',
        why: 'x is the number that makes the original equation true.',
        calc: 'x = $r',
      ),
    ],
  );
}

// ── Rectangle ────────────────────────────────────────────────────────────────

SchoolMathSolution? _parseRectangle(String q) {
  final isArea = q.contains('area');
  final isPerim = q.contains('perimeter') || q.contains('perimetre');
  if (!isArea && !isPerim) return null;
  if (!q.contains('rectangle') && !q.contains('rectangl')) {
    // still allow "area of 5 by 8" / "5 cm by 8 cm"
    if (!RegExp(r'\bby\b|\b×\b|\bx\b').hasMatch(q)) return null;
  }
  final nums = RegExp(r'(\d+(?:\.\d+)?)')
      .allMatches(q)
      .map((m) => double.parse(m.group(1)!))
      .toList();
  if (nums.length < 2) return null;
  final l = nums[0];
  final w = nums[1];
  if (isPerim) {
    final p = 2 * (l + w);
    return SchoolMathSolution(
      numericAnswer: p,
      answer: fmtNum(p),
      hint: 'Perimeter of a rectangle is 2 × (length + width). Add the sides first, then double.',
      practiceQuestion:
          'What is the perimeter of a rectangle ${fmtNum(_variant(l))} by ${fmtNum(w)}?',
      steps: [
        const MathStep(
          title: 'Recall the perimeter formula',
          why: 'A rectangle has two lengths and two widths.',
          formula: 'P = 2 × (L + W)',
        ),
        MathStep(
          title: 'Substitute',
          why: 'Length is ${fmtNum(l)} and width is ${fmtNum(w)}.',
          formula: 'P = 2 × (${fmtNum(l)} + ${fmtNum(w)})',
        ),
        MathStep(
          title: 'Add inside the brackets',
          why: 'Parentheses first.',
          calc: '${fmtNum(l)} + ${fmtNum(w)} = ${fmtNum(l + w)}',
        ),
        MathStep(
          title: 'Multiply by 2',
          why: 'Two pairs of sides.',
          calc: '2 × ${fmtNum(l + w)} = ${fmtNum(p)}',
        ),
        MathStep(
          title: 'State the perimeter',
          why: 'Attach length units if the question gave them.',
          calc: 'P = ${fmtNum(p)}',
        ),
      ],
    );
  }
  final area = l * w;
  return SchoolMathSolution(
    numericAnswer: area,
    answer: fmtNum(area),
    hint: 'Area of a rectangle is length × width. Multiply the two side lengths.',
    practiceQuestion:
        'What is the area of a rectangle ${fmtNum(_variant(l))} by ${fmtNum(w)}?',
    steps: [
      const MathStep(
        title: 'Recall the area formula',
        why: 'Area is the space inside the rectangle.',
        formula: 'A = L × W',
      ),
      MathStep(
        title: 'Substitute',
        why: 'Length is ${fmtNum(l)} and width is ${fmtNum(w)}.',
        formula: 'A = ${fmtNum(l)} × ${fmtNum(w)}',
      ),
      MathStep(
        title: 'Execute the arithmetic',
        why: 'Multiply the two lengths.',
        calc: '${fmtNum(l)} × ${fmtNum(w)} = ${fmtNum(area)}',
      ),
      MathStep(
        title: 'State the area',
        why: 'Square units if the question gave a length unit.',
        calc: 'A = ${fmtNum(area)}',
      ),
    ],
  );
}

// ── Arithmetic (PEMDAS) ──────────────────────────────────────────────────────

SchoolMathSolution? _parseArithmetic(String q) {
  final words = q.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
  const allowed = {
    'what', 'is', 'calculate', 'compute', 'evaluate', 'find', 'the', 'value',
    'of', 'equals', 'equal', 'please', 'work', 'out', 'answer',
  };
  final extra = words.where((w) => !allowed.contains(w)).toList();
  if (extra.length > 2) return null;

  var expr = q;
  expr = expr.replaceAll(
    RegExp(
      r'\b(what is|calculate|compute|evaluate|find the value of|find|work out|equals?)\b',
    ),
    '',
  );
  expr = expr.replaceAll(RegExp(r'[^0-9+\-*/x×÷().\s]'), '');
  expr = expr.replaceAll('×', '*').replaceAll('÷', '/');
  expr = expr.replaceAll(RegExp(r'(\d)\s*[xX]\s*(\d)'), r'$1*$2');
  expr = expr.replaceAll(' ', '');
  if (!RegExp(r'\d').hasMatch(expr)) return null;
  if (!RegExp(r'[+\-*/]').hasMatch(expr)) return null;

  final parsed = _tryEval(expr);
  if (parsed == null) return null;
  final result = parsed;
  final display = expr
      .replaceAll('*', ' × ')
      .replaceAll('/', ' ÷ ')
      .replaceAll('+', ' + ')
      .replaceAll('-', ' − ');

  return SchoolMathSolution(
    numericAnswer: result,
    answer: fmtNum(result),
    hint: 'Use order of operations: brackets first, then × and ÷ (left to right), then + and −.',
    practiceQuestion: 'Calculate ${_tweakExpr(expr)}.',
    steps: [
      MathStep(
        title: 'Write the expression',
        why: 'Keep the same numbers and operations as the question.',
        formula: display.trim(),
      ),
      const MathStep(
        title: 'Apply order of operations',
        why: 'Parentheses, then multiply/divide, then add/subtract — left to right.',
        formula: 'PEMDAS / BODMAS',
      ),
      MathStep(
        title: 'Execute the arithmetic',
        why: 'Each operation uses only the values produced by the previous one.',
        calc: '${display.trim()} = ${fmtNum(result)}',
      ),
      MathStep(
        title: 'State the value',
        why: 'This is the exact value of the expression.',
        calc: fmtNum(result),
      ),
    ],
  );
}

String _tweakExpr(String expr) {
  return expr.replaceFirstMapped(RegExp(r'\d+(?:\.\d+)?'), (m) {
    final n = double.parse(m.group(0)!);
    return fmtNum(_variant(n));
  }).replaceAll('*', ' × ').replaceAll('/', ' ÷ ');
}

double? _tryEval(String expr) {
  try {
    final p = _ArithParser(expr);
    final v = p.parse();
    if (!p.atEnd) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } catch (_) {
    return null;
  }
}

class _ArithParser {
  _ArithParser(this.src);
  final String src;
  int i = 0;

  bool get atEnd => i >= src.length;

  double parse() => _expr();

  double _expr() {
    var v = _term();
    while (!atEnd) {
      final c = src[i];
      if (c == '+') {
        i++;
        v += _term();
      } else if (c == '-') {
        i++;
        v -= _term();
      } else {
        break;
      }
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (!atEnd) {
      final c = src[i];
      if (c == '*') {
        i++;
        v *= _factor();
      } else if (c == '/') {
        i++;
        final d = _factor();
        if (d == 0) throw StateError('div0');
        v /= d;
      } else {
        break;
      }
    }
    return v;
  }

  double _factor() {
    if (atEnd) throw StateError('eof');
    if (src[i] == '+') {
      i++;
      return _factor();
    }
    if (src[i] == '-') {
      i++;
      return -_factor();
    }
    if (src[i] == '(') {
      i++;
      final v = _expr();
      if (atEnd || src[i] != ')') throw StateError('paren');
      i++;
      return v;
    }
    final start = i;
    if (src[i] == '.') {
      // .5
    } else if (!RegExp(r'\d').hasMatch(src[i])) {
      throw StateError('num');
    }
    while (!atEnd && RegExp(r'[0-9.]').hasMatch(src[i])) {
      i++;
    }
    final n = double.tryParse(src.substring(start, i));
    if (n == null) throw StateError('num');
    return n;
  }
}
