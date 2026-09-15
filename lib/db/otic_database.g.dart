// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'otic_database.dart';

// ignore_for_file: type=lint
class $StudentsTable extends Students with TableInfo<$StudentsTable, Student> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ageMeta = const VerificationMeta('age');
  @override
  late final GeneratedColumn<int> age = GeneratedColumn<int>(
    'age',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gradeMeta = const VerificationMeta('grade');
  @override
  late final GeneratedColumn<String> grade = GeneratedColumn<String>(
    'grade',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en'),
  );
  static const VerificationMeta _interestsJsonMeta = const VerificationMeta(
    'interestsJson',
  );
  @override
  late final GeneratedColumn<String> interestsJson = GeneratedColumn<String>(
    'interests_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _learningStyleMeta = const VerificationMeta(
    'learningStyle',
  );
  @override
  late final GeneratedColumn<String> learningStyle = GeneratedColumn<String>(
    'learning_style',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _strengthsJsonMeta = const VerificationMeta(
    'strengthsJson',
  );
  @override
  late final GeneratedColumn<String> strengthsJson = GeneratedColumn<String>(
    'strengths_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _weaknessesJsonMeta = const VerificationMeta(
    'weaknessesJson',
  );
  @override
  late final GeneratedColumn<String> weaknessesJson = GeneratedColumn<String>(
    'weaknesses_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _goalsJsonMeta = const VerificationMeta(
    'goalsJson',
  );
  @override
  late final GeneratedColumn<String> goalsJson = GeneratedColumn<String>(
    'goals_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _streakDaysMeta = const VerificationMeta(
    'streakDays',
  );
  @override
  late final GeneratedColumn<int> streakDays = GeneratedColumn<int>(
    'streak_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastStreakDateMeta = const VerificationMeta(
    'lastStreakDate',
  );
  @override
  late final GeneratedColumn<DateTime> lastStreakDate =
      GeneratedColumn<DateTime>(
        'last_streak_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _totalPointsMeta = const VerificationMeta(
    'totalPoints',
  );
  @override
  late final GeneratedColumn<int> totalPoints = GeneratedColumn<int>(
    'total_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastActiveAtMeta = const VerificationMeta(
    'lastActiveAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastActiveAt = GeneratedColumn<DateTime>(
    'last_active_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    age,
    grade,
    language,
    interestsJson,
    learningStyle,
    strengthsJson,
    weaknessesJson,
    goalsJson,
    streakDays,
    lastStreakDate,
    totalPoints,
    createdAt,
    lastActiveAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'students';
  @override
  VerificationContext validateIntegrity(
    Insertable<Student> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('age')) {
      context.handle(
        _ageMeta,
        age.isAcceptableOrUnknown(data['age']!, _ageMeta),
      );
    }
    if (data.containsKey('grade')) {
      context.handle(
        _gradeMeta,
        grade.isAcceptableOrUnknown(data['grade']!, _gradeMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('interests_json')) {
      context.handle(
        _interestsJsonMeta,
        interestsJson.isAcceptableOrUnknown(
          data['interests_json']!,
          _interestsJsonMeta,
        ),
      );
    }
    if (data.containsKey('learning_style')) {
      context.handle(
        _learningStyleMeta,
        learningStyle.isAcceptableOrUnknown(
          data['learning_style']!,
          _learningStyleMeta,
        ),
      );
    }
    if (data.containsKey('strengths_json')) {
      context.handle(
        _strengthsJsonMeta,
        strengthsJson.isAcceptableOrUnknown(
          data['strengths_json']!,
          _strengthsJsonMeta,
        ),
      );
    }
    if (data.containsKey('weaknesses_json')) {
      context.handle(
        _weaknessesJsonMeta,
        weaknessesJson.isAcceptableOrUnknown(
          data['weaknesses_json']!,
          _weaknessesJsonMeta,
        ),
      );
    }
    if (data.containsKey('goals_json')) {
      context.handle(
        _goalsJsonMeta,
        goalsJson.isAcceptableOrUnknown(data['goals_json']!, _goalsJsonMeta),
      );
    }
    if (data.containsKey('streak_days')) {
      context.handle(
        _streakDaysMeta,
        streakDays.isAcceptableOrUnknown(data['streak_days']!, _streakDaysMeta),
      );
    }
    if (data.containsKey('last_streak_date')) {
      context.handle(
        _lastStreakDateMeta,
        lastStreakDate.isAcceptableOrUnknown(
          data['last_streak_date']!,
          _lastStreakDateMeta,
        ),
      );
    }
    if (data.containsKey('total_points')) {
      context.handle(
        _totalPointsMeta,
        totalPoints.isAcceptableOrUnknown(
          data['total_points']!,
          _totalPointsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_active_at')) {
      context.handle(
        _lastActiveAtMeta,
        lastActiveAt.isAcceptableOrUnknown(
          data['last_active_at']!,
          _lastActiveAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Student map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Student(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      age: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}age'],
      ),
      grade: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grade'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      interestsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}interests_json'],
      )!,
      learningStyle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}learning_style'],
      )!,
      strengthsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strengths_json'],
      )!,
      weaknessesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weaknesses_json'],
      )!,
      goalsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goals_json'],
      )!,
      streakDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}streak_days'],
      )!,
      lastStreakDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_streak_date'],
      ),
      totalPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_points'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastActiveAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_active_at'],
      )!,
    );
  }

  @override
  $StudentsTable createAlias(String alias) {
    return $StudentsTable(attachedDatabase, alias);
  }
}

class Student extends DataClass implements Insertable<Student> {
  final int id;
  final String name;
  final int? age;
  final String? grade;
  final String language;
  final String interestsJson;
  final String learningStyle;
  final String strengthsJson;
  final String weaknessesJson;
  final String goalsJson;
  final int streakDays;
  final DateTime? lastStreakDate;
  final int totalPoints;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  const Student({
    required this.id,
    required this.name,
    this.age,
    this.grade,
    required this.language,
    required this.interestsJson,
    required this.learningStyle,
    required this.strengthsJson,
    required this.weaknessesJson,
    required this.goalsJson,
    required this.streakDays,
    this.lastStreakDate,
    required this.totalPoints,
    required this.createdAt,
    required this.lastActiveAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || age != null) {
      map['age'] = Variable<int>(age);
    }
    if (!nullToAbsent || grade != null) {
      map['grade'] = Variable<String>(grade);
    }
    map['language'] = Variable<String>(language);
    map['interests_json'] = Variable<String>(interestsJson);
    map['learning_style'] = Variable<String>(learningStyle);
    map['strengths_json'] = Variable<String>(strengthsJson);
    map['weaknesses_json'] = Variable<String>(weaknessesJson);
    map['goals_json'] = Variable<String>(goalsJson);
    map['streak_days'] = Variable<int>(streakDays);
    if (!nullToAbsent || lastStreakDate != null) {
      map['last_streak_date'] = Variable<DateTime>(lastStreakDate);
    }
    map['total_points'] = Variable<int>(totalPoints);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_active_at'] = Variable<DateTime>(lastActiveAt);
    return map;
  }

  StudentsCompanion toCompanion(bool nullToAbsent) {
    return StudentsCompanion(
      id: Value(id),
      name: Value(name),
      age: age == null && nullToAbsent ? const Value.absent() : Value(age),
      grade: grade == null && nullToAbsent
          ? const Value.absent()
          : Value(grade),
      language: Value(language),
      interestsJson: Value(interestsJson),
      learningStyle: Value(learningStyle),
      strengthsJson: Value(strengthsJson),
      weaknessesJson: Value(weaknessesJson),
      goalsJson: Value(goalsJson),
      streakDays: Value(streakDays),
      lastStreakDate: lastStreakDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStreakDate),
      totalPoints: Value(totalPoints),
      createdAt: Value(createdAt),
      lastActiveAt: Value(lastActiveAt),
    );
  }

  factory Student.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Student(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      age: serializer.fromJson<int?>(json['age']),
      grade: serializer.fromJson<String?>(json['grade']),
      language: serializer.fromJson<String>(json['language']),
      interestsJson: serializer.fromJson<String>(json['interestsJson']),
      learningStyle: serializer.fromJson<String>(json['learningStyle']),
      strengthsJson: serializer.fromJson<String>(json['strengthsJson']),
      weaknessesJson: serializer.fromJson<String>(json['weaknessesJson']),
      goalsJson: serializer.fromJson<String>(json['goalsJson']),
      streakDays: serializer.fromJson<int>(json['streakDays']),
      lastStreakDate: serializer.fromJson<DateTime?>(json['lastStreakDate']),
      totalPoints: serializer.fromJson<int>(json['totalPoints']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastActiveAt: serializer.fromJson<DateTime>(json['lastActiveAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'age': serializer.toJson<int?>(age),
      'grade': serializer.toJson<String?>(grade),
      'language': serializer.toJson<String>(language),
      'interestsJson': serializer.toJson<String>(interestsJson),
      'learningStyle': serializer.toJson<String>(learningStyle),
      'strengthsJson': serializer.toJson<String>(strengthsJson),
      'weaknessesJson': serializer.toJson<String>(weaknessesJson),
      'goalsJson': serializer.toJson<String>(goalsJson),
      'streakDays': serializer.toJson<int>(streakDays),
      'lastStreakDate': serializer.toJson<DateTime?>(lastStreakDate),
      'totalPoints': serializer.toJson<int>(totalPoints),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastActiveAt': serializer.toJson<DateTime>(lastActiveAt),
    };
  }

  Student copyWith({
    int? id,
    String? name,
    Value<int?> age = const Value.absent(),
    Value<String?> grade = const Value.absent(),
    String? language,
    String? interestsJson,
    String? learningStyle,
    String? strengthsJson,
    String? weaknessesJson,
    String? goalsJson,
    int? streakDays,
    Value<DateTime?> lastStreakDate = const Value.absent(),
    int? totalPoints,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  }) => Student(
    id: id ?? this.id,
    name: name ?? this.name,
    age: age.present ? age.value : this.age,
    grade: grade.present ? grade.value : this.grade,
    language: language ?? this.language,
    interestsJson: interestsJson ?? this.interestsJson,
    learningStyle: learningStyle ?? this.learningStyle,
    strengthsJson: strengthsJson ?? this.strengthsJson,
    weaknessesJson: weaknessesJson ?? this.weaknessesJson,
    goalsJson: goalsJson ?? this.goalsJson,
    streakDays: streakDays ?? this.streakDays,
    lastStreakDate: lastStreakDate.present
        ? lastStreakDate.value
        : this.lastStreakDate,
    totalPoints: totalPoints ?? this.totalPoints,
    createdAt: createdAt ?? this.createdAt,
    lastActiveAt: lastActiveAt ?? this.lastActiveAt,
  );
  Student copyWithCompanion(StudentsCompanion data) {
    return Student(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      age: data.age.present ? data.age.value : this.age,
      grade: data.grade.present ? data.grade.value : this.grade,
      language: data.language.present ? data.language.value : this.language,
      interestsJson: data.interestsJson.present
          ? data.interestsJson.value
          : this.interestsJson,
      learningStyle: data.learningStyle.present
          ? data.learningStyle.value
          : this.learningStyle,
      strengthsJson: data.strengthsJson.present
          ? data.strengthsJson.value
          : this.strengthsJson,
      weaknessesJson: data.weaknessesJson.present
          ? data.weaknessesJson.value
          : this.weaknessesJson,
      goalsJson: data.goalsJson.present ? data.goalsJson.value : this.goalsJson,
      streakDays: data.streakDays.present
          ? data.streakDays.value
          : this.streakDays,
      lastStreakDate: data.lastStreakDate.present
          ? data.lastStreakDate.value
          : this.lastStreakDate,
      totalPoints: data.totalPoints.present
          ? data.totalPoints.value
          : this.totalPoints,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastActiveAt: data.lastActiveAt.present
          ? data.lastActiveAt.value
          : this.lastActiveAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Student(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('age: $age, ')
          ..write('grade: $grade, ')
          ..write('language: $language, ')
          ..write('interestsJson: $interestsJson, ')
          ..write('learningStyle: $learningStyle, ')
          ..write('strengthsJson: $strengthsJson, ')
          ..write('weaknessesJson: $weaknessesJson, ')
          ..write('goalsJson: $goalsJson, ')
          ..write('streakDays: $streakDays, ')
          ..write('lastStreakDate: $lastStreakDate, ')
          ..write('totalPoints: $totalPoints, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastActiveAt: $lastActiveAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    age,
    grade,
    language,
    interestsJson,
    learningStyle,
    strengthsJson,
    weaknessesJson,
    goalsJson,
    streakDays,
    lastStreakDate,
    totalPoints,
    createdAt,
    lastActiveAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Student &&
          other.id == this.id &&
          other.name == this.name &&
          other.age == this.age &&
          other.grade == this.grade &&
          other.language == this.language &&
          other.interestsJson == this.interestsJson &&
          other.learningStyle == this.learningStyle &&
          other.strengthsJson == this.strengthsJson &&
          other.weaknessesJson == this.weaknessesJson &&
          other.goalsJson == this.goalsJson &&
          other.streakDays == this.streakDays &&
          other.lastStreakDate == this.lastStreakDate &&
          other.totalPoints == this.totalPoints &&
          other.createdAt == this.createdAt &&
          other.lastActiveAt == this.lastActiveAt);
}

class StudentsCompanion extends UpdateCompanion<Student> {
  final Value<int> id;
  final Value<String> name;
  final Value<int?> age;
  final Value<String?> grade;
  final Value<String> language;
  final Value<String> interestsJson;
  final Value<String> learningStyle;
  final Value<String> strengthsJson;
  final Value<String> weaknessesJson;
  final Value<String> goalsJson;
  final Value<int> streakDays;
  final Value<DateTime?> lastStreakDate;
  final Value<int> totalPoints;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastActiveAt;
  const StudentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.age = const Value.absent(),
    this.grade = const Value.absent(),
    this.language = const Value.absent(),
    this.interestsJson = const Value.absent(),
    this.learningStyle = const Value.absent(),
    this.strengthsJson = const Value.absent(),
    this.weaknessesJson = const Value.absent(),
    this.goalsJson = const Value.absent(),
    this.streakDays = const Value.absent(),
    this.lastStreakDate = const Value.absent(),
    this.totalPoints = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastActiveAt = const Value.absent(),
  });
  StudentsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.age = const Value.absent(),
    this.grade = const Value.absent(),
    this.language = const Value.absent(),
    this.interestsJson = const Value.absent(),
    this.learningStyle = const Value.absent(),
    this.strengthsJson = const Value.absent(),
    this.weaknessesJson = const Value.absent(),
    this.goalsJson = const Value.absent(),
    this.streakDays = const Value.absent(),
    this.lastStreakDate = const Value.absent(),
    this.totalPoints = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastActiveAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Student> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? age,
    Expression<String>? grade,
    Expression<String>? language,
    Expression<String>? interestsJson,
    Expression<String>? learningStyle,
    Expression<String>? strengthsJson,
    Expression<String>? weaknessesJson,
    Expression<String>? goalsJson,
    Expression<int>? streakDays,
    Expression<DateTime>? lastStreakDate,
    Expression<int>? totalPoints,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastActiveAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (age != null) 'age': age,
      if (grade != null) 'grade': grade,
      if (language != null) 'language': language,
      if (interestsJson != null) 'interests_json': interestsJson,
      if (learningStyle != null) 'learning_style': learningStyle,
      if (strengthsJson != null) 'strengths_json': strengthsJson,
      if (weaknessesJson != null) 'weaknesses_json': weaknessesJson,
      if (goalsJson != null) 'goals_json': goalsJson,
      if (streakDays != null) 'streak_days': streakDays,
      if (lastStreakDate != null) 'last_streak_date': lastStreakDate,
      if (totalPoints != null) 'total_points': totalPoints,
      if (createdAt != null) 'created_at': createdAt,
      if (lastActiveAt != null) 'last_active_at': lastActiveAt,
    });
  }

  StudentsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int?>? age,
    Value<String?>? grade,
    Value<String>? language,
    Value<String>? interestsJson,
    Value<String>? learningStyle,
    Value<String>? strengthsJson,
    Value<String>? weaknessesJson,
    Value<String>? goalsJson,
    Value<int>? streakDays,
    Value<DateTime?>? lastStreakDate,
    Value<int>? totalPoints,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastActiveAt,
  }) {
    return StudentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      grade: grade ?? this.grade,
      language: language ?? this.language,
      interestsJson: interestsJson ?? this.interestsJson,
      learningStyle: learningStyle ?? this.learningStyle,
      strengthsJson: strengthsJson ?? this.strengthsJson,
      weaknessesJson: weaknessesJson ?? this.weaknessesJson,
      goalsJson: goalsJson ?? this.goalsJson,
      streakDays: streakDays ?? this.streakDays,
      lastStreakDate: lastStreakDate ?? this.lastStreakDate,
      totalPoints: totalPoints ?? this.totalPoints,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (age.present) {
      map['age'] = Variable<int>(age.value);
    }
    if (grade.present) {
      map['grade'] = Variable<String>(grade.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (interestsJson.present) {
      map['interests_json'] = Variable<String>(interestsJson.value);
    }
    if (learningStyle.present) {
      map['learning_style'] = Variable<String>(learningStyle.value);
    }
    if (strengthsJson.present) {
      map['strengths_json'] = Variable<String>(strengthsJson.value);
    }
    if (weaknessesJson.present) {
      map['weaknesses_json'] = Variable<String>(weaknessesJson.value);
    }
    if (goalsJson.present) {
      map['goals_json'] = Variable<String>(goalsJson.value);
    }
    if (streakDays.present) {
      map['streak_days'] = Variable<int>(streakDays.value);
    }
    if (lastStreakDate.present) {
      map['last_streak_date'] = Variable<DateTime>(lastStreakDate.value);
    }
    if (totalPoints.present) {
      map['total_points'] = Variable<int>(totalPoints.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastActiveAt.present) {
      map['last_active_at'] = Variable<DateTime>(lastActiveAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('age: $age, ')
          ..write('grade: $grade, ')
          ..write('language: $language, ')
          ..write('interestsJson: $interestsJson, ')
          ..write('learningStyle: $learningStyle, ')
          ..write('strengthsJson: $strengthsJson, ')
          ..write('weaknessesJson: $weaknessesJson, ')
          ..write('goalsJson: $goalsJson, ')
          ..write('streakDays: $streakDays, ')
          ..write('lastStreakDate: $lastStreakDate, ')
          ..write('totalPoints: $totalPoints, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastActiveAt: $lastActiveAt')
          ..write(')'))
        .toString();
  }
}

class $SessionSummariesTable extends SessionSummaries
    with TableInfo<$SessionSummariesTable, SessionSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strengthsJsonMeta = const VerificationMeta(
    'strengthsJson',
  );
  @override
  late final GeneratedColumn<String> strengthsJson = GeneratedColumn<String>(
    'strengths_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _weaknessesJsonMeta = const VerificationMeta(
    'weaknessesJson',
  );
  @override
  late final GeneratedColumn<String> weaknessesJson = GeneratedColumn<String>(
    'weaknesses_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _highestStageMeta = const VerificationMeta(
    'highestStage',
  );
  @override
  late final GeneratedColumn<String> highestStage = GeneratedColumn<String>(
    'highest_stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('answer'),
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  @override
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sessionAtMeta = const VerificationMeta(
    'sessionAt',
  );
  @override
  late final GeneratedColumn<DateTime> sessionAt = GeneratedColumn<DateTime>(
    'session_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    topic,
    summary,
    strengthsJson,
    weaknessesJson,
    highestStage,
    messageCount,
    sessionAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionSummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('strengths_json')) {
      context.handle(
        _strengthsJsonMeta,
        strengthsJson.isAcceptableOrUnknown(
          data['strengths_json']!,
          _strengthsJsonMeta,
        ),
      );
    }
    if (data.containsKey('weaknesses_json')) {
      context.handle(
        _weaknessesJsonMeta,
        weaknessesJson.isAcceptableOrUnknown(
          data['weaknesses_json']!,
          _weaknessesJsonMeta,
        ),
      );
    }
    if (data.containsKey('highest_stage')) {
      context.handle(
        _highestStageMeta,
        highestStage.isAcceptableOrUnknown(
          data['highest_stage']!,
          _highestStageMeta,
        ),
      );
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    }
    if (data.containsKey('session_at')) {
      context.handle(
        _sessionAtMeta,
        sessionAt.isAcceptableOrUnknown(data['session_at']!, _sessionAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionSummary(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      strengthsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strengths_json'],
      )!,
      weaknessesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weaknesses_json'],
      )!,
      highestStage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}highest_stage'],
      )!,
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      )!,
      sessionAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}session_at'],
      )!,
    );
  }

  @override
  $SessionSummariesTable createAlias(String alias) {
    return $SessionSummariesTable(attachedDatabase, alias);
  }
}

class SessionSummary extends DataClass implements Insertable<SessionSummary> {
  final int id;
  final int studentId;
  final String topic;
  final String summary;
  final String strengthsJson;
  final String weaknessesJson;
  final String highestStage;
  final int messageCount;
  final DateTime sessionAt;
  const SessionSummary({
    required this.id,
    required this.studentId,
    required this.topic,
    required this.summary,
    required this.strengthsJson,
    required this.weaknessesJson,
    required this.highestStage,
    required this.messageCount,
    required this.sessionAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['topic'] = Variable<String>(topic);
    map['summary'] = Variable<String>(summary);
    map['strengths_json'] = Variable<String>(strengthsJson);
    map['weaknesses_json'] = Variable<String>(weaknessesJson);
    map['highest_stage'] = Variable<String>(highestStage);
    map['message_count'] = Variable<int>(messageCount);
    map['session_at'] = Variable<DateTime>(sessionAt);
    return map;
  }

  SessionSummariesCompanion toCompanion(bool nullToAbsent) {
    return SessionSummariesCompanion(
      id: Value(id),
      studentId: Value(studentId),
      topic: Value(topic),
      summary: Value(summary),
      strengthsJson: Value(strengthsJson),
      weaknessesJson: Value(weaknessesJson),
      highestStage: Value(highestStage),
      messageCount: Value(messageCount),
      sessionAt: Value(sessionAt),
    );
  }

  factory SessionSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionSummary(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      topic: serializer.fromJson<String>(json['topic']),
      summary: serializer.fromJson<String>(json['summary']),
      strengthsJson: serializer.fromJson<String>(json['strengthsJson']),
      weaknessesJson: serializer.fromJson<String>(json['weaknessesJson']),
      highestStage: serializer.fromJson<String>(json['highestStage']),
      messageCount: serializer.fromJson<int>(json['messageCount']),
      sessionAt: serializer.fromJson<DateTime>(json['sessionAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'topic': serializer.toJson<String>(topic),
      'summary': serializer.toJson<String>(summary),
      'strengthsJson': serializer.toJson<String>(strengthsJson),
      'weaknessesJson': serializer.toJson<String>(weaknessesJson),
      'highestStage': serializer.toJson<String>(highestStage),
      'messageCount': serializer.toJson<int>(messageCount),
      'sessionAt': serializer.toJson<DateTime>(sessionAt),
    };
  }

  SessionSummary copyWith({
    int? id,
    int? studentId,
    String? topic,
    String? summary,
    String? strengthsJson,
    String? weaknessesJson,
    String? highestStage,
    int? messageCount,
    DateTime? sessionAt,
  }) => SessionSummary(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    topic: topic ?? this.topic,
    summary: summary ?? this.summary,
    strengthsJson: strengthsJson ?? this.strengthsJson,
    weaknessesJson: weaknessesJson ?? this.weaknessesJson,
    highestStage: highestStage ?? this.highestStage,
    messageCount: messageCount ?? this.messageCount,
    sessionAt: sessionAt ?? this.sessionAt,
  );
  SessionSummary copyWithCompanion(SessionSummariesCompanion data) {
    return SessionSummary(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      topic: data.topic.present ? data.topic.value : this.topic,
      summary: data.summary.present ? data.summary.value : this.summary,
      strengthsJson: data.strengthsJson.present
          ? data.strengthsJson.value
          : this.strengthsJson,
      weaknessesJson: data.weaknessesJson.present
          ? data.weaknessesJson.value
          : this.weaknessesJson,
      highestStage: data.highestStage.present
          ? data.highestStage.value
          : this.highestStage,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      sessionAt: data.sessionAt.present ? data.sessionAt.value : this.sessionAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionSummary(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('summary: $summary, ')
          ..write('strengthsJson: $strengthsJson, ')
          ..write('weaknessesJson: $weaknessesJson, ')
          ..write('highestStage: $highestStage, ')
          ..write('messageCount: $messageCount, ')
          ..write('sessionAt: $sessionAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    studentId,
    topic,
    summary,
    strengthsJson,
    weaknessesJson,
    highestStage,
    messageCount,
    sessionAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionSummary &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.topic == this.topic &&
          other.summary == this.summary &&
          other.strengthsJson == this.strengthsJson &&
          other.weaknessesJson == this.weaknessesJson &&
          other.highestStage == this.highestStage &&
          other.messageCount == this.messageCount &&
          other.sessionAt == this.sessionAt);
}

class SessionSummariesCompanion extends UpdateCompanion<SessionSummary> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> topic;
  final Value<String> summary;
  final Value<String> strengthsJson;
  final Value<String> weaknessesJson;
  final Value<String> highestStage;
  final Value<int> messageCount;
  final Value<DateTime> sessionAt;
  const SessionSummariesCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.topic = const Value.absent(),
    this.summary = const Value.absent(),
    this.strengthsJson = const Value.absent(),
    this.weaknessesJson = const Value.absent(),
    this.highestStage = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.sessionAt = const Value.absent(),
  });
  SessionSummariesCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String topic,
    required String summary,
    this.strengthsJson = const Value.absent(),
    this.weaknessesJson = const Value.absent(),
    this.highestStage = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.sessionAt = const Value.absent(),
  }) : studentId = Value(studentId),
       topic = Value(topic),
       summary = Value(summary);
  static Insertable<SessionSummary> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? topic,
    Expression<String>? summary,
    Expression<String>? strengthsJson,
    Expression<String>? weaknessesJson,
    Expression<String>? highestStage,
    Expression<int>? messageCount,
    Expression<DateTime>? sessionAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (topic != null) 'topic': topic,
      if (summary != null) 'summary': summary,
      if (strengthsJson != null) 'strengths_json': strengthsJson,
      if (weaknessesJson != null) 'weaknesses_json': weaknessesJson,
      if (highestStage != null) 'highest_stage': highestStage,
      if (messageCount != null) 'message_count': messageCount,
      if (sessionAt != null) 'session_at': sessionAt,
    });
  }

  SessionSummariesCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? topic,
    Value<String>? summary,
    Value<String>? strengthsJson,
    Value<String>? weaknessesJson,
    Value<String>? highestStage,
    Value<int>? messageCount,
    Value<DateTime>? sessionAt,
  }) {
    return SessionSummariesCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      topic: topic ?? this.topic,
      summary: summary ?? this.summary,
      strengthsJson: strengthsJson ?? this.strengthsJson,
      weaknessesJson: weaknessesJson ?? this.weaknessesJson,
      highestStage: highestStage ?? this.highestStage,
      messageCount: messageCount ?? this.messageCount,
      sessionAt: sessionAt ?? this.sessionAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (strengthsJson.present) {
      map['strengths_json'] = Variable<String>(strengthsJson.value);
    }
    if (weaknessesJson.present) {
      map['weaknesses_json'] = Variable<String>(weaknessesJson.value);
    }
    if (highestStage.present) {
      map['highest_stage'] = Variable<String>(highestStage.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (sessionAt.present) {
      map['session_at'] = Variable<DateTime>(sessionAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionSummariesCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('summary: $summary, ')
          ..write('strengthsJson: $strengthsJson, ')
          ..write('weaknessesJson: $weaknessesJson, ')
          ..write('highestStage: $highestStage, ')
          ..write('messageCount: $messageCount, ')
          ..write('sessionAt: $sessionAt')
          ..write(')'))
        .toString();
  }
}

class $TopicProgressTable extends TopicProgress
    with TableInfo<$TopicProgressTable, TopicProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TopicProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sessionsCountMeta = const VerificationMeta(
    'sessionsCount',
  );
  @override
  late final GeneratedColumn<int> sessionsCount = GeneratedColumn<int>(
    'sessions_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastStudiedAtMeta = const VerificationMeta(
    'lastStudiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastStudiedAt =
      GeneratedColumn<DateTime>(
        'last_studied_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: currentDateAndTime,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    topic,
    level,
    sessionsCount,
    lastStudiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'topic_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<TopicProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('sessions_count')) {
      context.handle(
        _sessionsCountMeta,
        sessionsCount.isAcceptableOrUnknown(
          data['sessions_count']!,
          _sessionsCountMeta,
        ),
      );
    }
    if (data.containsKey('last_studied_at')) {
      context.handle(
        _lastStudiedAtMeta,
        lastStudiedAt.isAcceptableOrUnknown(
          data['last_studied_at']!,
          _lastStudiedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {studentId, topic},
  ];
  @override
  TopicProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TopicProgressData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      sessionsCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sessions_count'],
      )!,
      lastStudiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_studied_at'],
      )!,
    );
  }

  @override
  $TopicProgressTable createAlias(String alias) {
    return $TopicProgressTable(attachedDatabase, alias);
  }
}

class TopicProgressData extends DataClass
    implements Insertable<TopicProgressData> {
  final int id;
  final int studentId;
  final String topic;
  final int level;
  final int sessionsCount;
  final DateTime lastStudiedAt;
  const TopicProgressData({
    required this.id,
    required this.studentId,
    required this.topic,
    required this.level,
    required this.sessionsCount,
    required this.lastStudiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['topic'] = Variable<String>(topic);
    map['level'] = Variable<int>(level);
    map['sessions_count'] = Variable<int>(sessionsCount);
    map['last_studied_at'] = Variable<DateTime>(lastStudiedAt);
    return map;
  }

  TopicProgressCompanion toCompanion(bool nullToAbsent) {
    return TopicProgressCompanion(
      id: Value(id),
      studentId: Value(studentId),
      topic: Value(topic),
      level: Value(level),
      sessionsCount: Value(sessionsCount),
      lastStudiedAt: Value(lastStudiedAt),
    );
  }

  factory TopicProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TopicProgressData(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      topic: serializer.fromJson<String>(json['topic']),
      level: serializer.fromJson<int>(json['level']),
      sessionsCount: serializer.fromJson<int>(json['sessionsCount']),
      lastStudiedAt: serializer.fromJson<DateTime>(json['lastStudiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'topic': serializer.toJson<String>(topic),
      'level': serializer.toJson<int>(level),
      'sessionsCount': serializer.toJson<int>(sessionsCount),
      'lastStudiedAt': serializer.toJson<DateTime>(lastStudiedAt),
    };
  }

  TopicProgressData copyWith({
    int? id,
    int? studentId,
    String? topic,
    int? level,
    int? sessionsCount,
    DateTime? lastStudiedAt,
  }) => TopicProgressData(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    topic: topic ?? this.topic,
    level: level ?? this.level,
    sessionsCount: sessionsCount ?? this.sessionsCount,
    lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
  );
  TopicProgressData copyWithCompanion(TopicProgressCompanion data) {
    return TopicProgressData(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      topic: data.topic.present ? data.topic.value : this.topic,
      level: data.level.present ? data.level.value : this.level,
      sessionsCount: data.sessionsCount.present
          ? data.sessionsCount.value
          : this.sessionsCount,
      lastStudiedAt: data.lastStudiedAt.present
          ? data.lastStudiedAt.value
          : this.lastStudiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TopicProgressData(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('level: $level, ')
          ..write('sessionsCount: $sessionsCount, ')
          ..write('lastStudiedAt: $lastStudiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, studentId, topic, level, sessionsCount, lastStudiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TopicProgressData &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.topic == this.topic &&
          other.level == this.level &&
          other.sessionsCount == this.sessionsCount &&
          other.lastStudiedAt == this.lastStudiedAt);
}

class TopicProgressCompanion extends UpdateCompanion<TopicProgressData> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> topic;
  final Value<int> level;
  final Value<int> sessionsCount;
  final Value<DateTime> lastStudiedAt;
  const TopicProgressCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.topic = const Value.absent(),
    this.level = const Value.absent(),
    this.sessionsCount = const Value.absent(),
    this.lastStudiedAt = const Value.absent(),
  });
  TopicProgressCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String topic,
    this.level = const Value.absent(),
    this.sessionsCount = const Value.absent(),
    this.lastStudiedAt = const Value.absent(),
  }) : studentId = Value(studentId),
       topic = Value(topic);
  static Insertable<TopicProgressData> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? topic,
    Expression<int>? level,
    Expression<int>? sessionsCount,
    Expression<DateTime>? lastStudiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (topic != null) 'topic': topic,
      if (level != null) 'level': level,
      if (sessionsCount != null) 'sessions_count': sessionsCount,
      if (lastStudiedAt != null) 'last_studied_at': lastStudiedAt,
    });
  }

  TopicProgressCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? topic,
    Value<int>? level,
    Value<int>? sessionsCount,
    Value<DateTime>? lastStudiedAt,
  }) {
    return TopicProgressCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      topic: topic ?? this.topic,
      level: level ?? this.level,
      sessionsCount: sessionsCount ?? this.sessionsCount,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (sessionsCount.present) {
      map['sessions_count'] = Variable<int>(sessionsCount.value);
    }
    if (lastStudiedAt.present) {
      map['last_studied_at'] = Variable<DateTime>(lastStudiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TopicProgressCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('level: $level, ')
          ..write('sessionsCount: $sessionsCount, ')
          ..write('lastStudiedAt: $lastStudiedAt')
          ..write(')'))
        .toString();
  }
}

class $LearningPathsTable extends LearningPaths
    with TableInfo<$LearningPathsTable, LearningPath> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningPathsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitsJsonMeta = const VerificationMeta(
    'unitsJson',
  );
  @override
  late final GeneratedColumn<String> unitsJson = GeneratedColumn<String>(
    'units_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _totalLessonsMeta = const VerificationMeta(
    'totalLessons',
  );
  @override
  late final GeneratedColumn<int> totalLessons = GeneratedColumn<int>(
    'total_lessons',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedLessonsMeta = const VerificationMeta(
    'completedLessons',
  );
  @override
  late final GeneratedColumn<int> completedLessons = GeneratedColumn<int>(
    'completed_lessons',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentUnitMeta = const VerificationMeta(
    'currentUnit',
  );
  @override
  late final GeneratedColumn<int> currentUnit = GeneratedColumn<int>(
    'current_unit',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentLessonMeta = const VerificationMeta(
    'currentLesson',
  );
  @override
  late final GeneratedColumn<int> currentLesson = GeneratedColumn<int>(
    'current_lesson',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> generatedAt = GeneratedColumn<DateTime>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessedAt =
      GeneratedColumn<DateTime>(
        'last_accessed_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: currentDateAndTime,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    topic,
    title,
    description,
    unitsJson,
    totalLessons,
    completedLessons,
    currentUnit,
    currentLesson,
    generatedAt,
    lastAccessedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_paths';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningPath> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('units_json')) {
      context.handle(
        _unitsJsonMeta,
        unitsJson.isAcceptableOrUnknown(data['units_json']!, _unitsJsonMeta),
      );
    }
    if (data.containsKey('total_lessons')) {
      context.handle(
        _totalLessonsMeta,
        totalLessons.isAcceptableOrUnknown(
          data['total_lessons']!,
          _totalLessonsMeta,
        ),
      );
    }
    if (data.containsKey('completed_lessons')) {
      context.handle(
        _completedLessonsMeta,
        completedLessons.isAcceptableOrUnknown(
          data['completed_lessons']!,
          _completedLessonsMeta,
        ),
      );
    }
    if (data.containsKey('current_unit')) {
      context.handle(
        _currentUnitMeta,
        currentUnit.isAcceptableOrUnknown(
          data['current_unit']!,
          _currentUnitMeta,
        ),
      );
    }
    if (data.containsKey('current_lesson')) {
      context.handle(
        _currentLessonMeta,
        currentLesson.isAcceptableOrUnknown(
          data['current_lesson']!,
          _currentLessonMeta,
        ),
      );
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {studentId, topic},
  ];
  @override
  LearningPath map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningPath(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      unitsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}units_json'],
      )!,
      totalLessons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_lessons'],
      )!,
      completedLessons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_lessons'],
      )!,
      currentUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_unit'],
      )!,
      currentLesson: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_lesson'],
      )!,
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}generated_at'],
      )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_accessed_at'],
      )!,
    );
  }

  @override
  $LearningPathsTable createAlias(String alias) {
    return $LearningPathsTable(attachedDatabase, alias);
  }
}

class LearningPath extends DataClass implements Insertable<LearningPath> {
  final int id;
  final int studentId;
  final String topic;
  final String title;
  final String description;
  final String unitsJson;
  final int totalLessons;
  final int completedLessons;
  final int currentUnit;
  final int currentLesson;
  final DateTime generatedAt;
  final DateTime lastAccessedAt;
  const LearningPath({
    required this.id,
    required this.studentId,
    required this.topic,
    required this.title,
    required this.description,
    required this.unitsJson,
    required this.totalLessons,
    required this.completedLessons,
    required this.currentUnit,
    required this.currentLesson,
    required this.generatedAt,
    required this.lastAccessedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['topic'] = Variable<String>(topic);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['units_json'] = Variable<String>(unitsJson);
    map['total_lessons'] = Variable<int>(totalLessons);
    map['completed_lessons'] = Variable<int>(completedLessons);
    map['current_unit'] = Variable<int>(currentUnit);
    map['current_lesson'] = Variable<int>(currentLesson);
    map['generated_at'] = Variable<DateTime>(generatedAt);
    map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt);
    return map;
  }

  LearningPathsCompanion toCompanion(bool nullToAbsent) {
    return LearningPathsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      topic: Value(topic),
      title: Value(title),
      description: Value(description),
      unitsJson: Value(unitsJson),
      totalLessons: Value(totalLessons),
      completedLessons: Value(completedLessons),
      currentUnit: Value(currentUnit),
      currentLesson: Value(currentLesson),
      generatedAt: Value(generatedAt),
      lastAccessedAt: Value(lastAccessedAt),
    );
  }

  factory LearningPath.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningPath(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      topic: serializer.fromJson<String>(json['topic']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      unitsJson: serializer.fromJson<String>(json['unitsJson']),
      totalLessons: serializer.fromJson<int>(json['totalLessons']),
      completedLessons: serializer.fromJson<int>(json['completedLessons']),
      currentUnit: serializer.fromJson<int>(json['currentUnit']),
      currentLesson: serializer.fromJson<int>(json['currentLesson']),
      generatedAt: serializer.fromJson<DateTime>(json['generatedAt']),
      lastAccessedAt: serializer.fromJson<DateTime>(json['lastAccessedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'topic': serializer.toJson<String>(topic),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'unitsJson': serializer.toJson<String>(unitsJson),
      'totalLessons': serializer.toJson<int>(totalLessons),
      'completedLessons': serializer.toJson<int>(completedLessons),
      'currentUnit': serializer.toJson<int>(currentUnit),
      'currentLesson': serializer.toJson<int>(currentLesson),
      'generatedAt': serializer.toJson<DateTime>(generatedAt),
      'lastAccessedAt': serializer.toJson<DateTime>(lastAccessedAt),
    };
  }

  LearningPath copyWith({
    int? id,
    int? studentId,
    String? topic,
    String? title,
    String? description,
    String? unitsJson,
    int? totalLessons,
    int? completedLessons,
    int? currentUnit,
    int? currentLesson,
    DateTime? generatedAt,
    DateTime? lastAccessedAt,
  }) => LearningPath(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    topic: topic ?? this.topic,
    title: title ?? this.title,
    description: description ?? this.description,
    unitsJson: unitsJson ?? this.unitsJson,
    totalLessons: totalLessons ?? this.totalLessons,
    completedLessons: completedLessons ?? this.completedLessons,
    currentUnit: currentUnit ?? this.currentUnit,
    currentLesson: currentLesson ?? this.currentLesson,
    generatedAt: generatedAt ?? this.generatedAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
  );
  LearningPath copyWithCompanion(LearningPathsCompanion data) {
    return LearningPath(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      topic: data.topic.present ? data.topic.value : this.topic,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      unitsJson: data.unitsJson.present ? data.unitsJson.value : this.unitsJson,
      totalLessons: data.totalLessons.present
          ? data.totalLessons.value
          : this.totalLessons,
      completedLessons: data.completedLessons.present
          ? data.completedLessons.value
          : this.completedLessons,
      currentUnit: data.currentUnit.present
          ? data.currentUnit.value
          : this.currentUnit,
      currentLesson: data.currentLesson.present
          ? data.currentLesson.value
          : this.currentLesson,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
      lastAccessedAt: data.lastAccessedAt.present
          ? data.lastAccessedAt.value
          : this.lastAccessedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningPath(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('unitsJson: $unitsJson, ')
          ..write('totalLessons: $totalLessons, ')
          ..write('completedLessons: $completedLessons, ')
          ..write('currentUnit: $currentUnit, ')
          ..write('currentLesson: $currentLesson, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    studentId,
    topic,
    title,
    description,
    unitsJson,
    totalLessons,
    completedLessons,
    currentUnit,
    currentLesson,
    generatedAt,
    lastAccessedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningPath &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.topic == this.topic &&
          other.title == this.title &&
          other.description == this.description &&
          other.unitsJson == this.unitsJson &&
          other.totalLessons == this.totalLessons &&
          other.completedLessons == this.completedLessons &&
          other.currentUnit == this.currentUnit &&
          other.currentLesson == this.currentLesson &&
          other.generatedAt == this.generatedAt &&
          other.lastAccessedAt == this.lastAccessedAt);
}

class LearningPathsCompanion extends UpdateCompanion<LearningPath> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> topic;
  final Value<String> title;
  final Value<String> description;
  final Value<String> unitsJson;
  final Value<int> totalLessons;
  final Value<int> completedLessons;
  final Value<int> currentUnit;
  final Value<int> currentLesson;
  final Value<DateTime> generatedAt;
  final Value<DateTime> lastAccessedAt;
  const LearningPathsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.topic = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.unitsJson = const Value.absent(),
    this.totalLessons = const Value.absent(),
    this.completedLessons = const Value.absent(),
    this.currentUnit = const Value.absent(),
    this.currentLesson = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
  });
  LearningPathsCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String topic,
    required String title,
    required String description,
    this.unitsJson = const Value.absent(),
    this.totalLessons = const Value.absent(),
    this.completedLessons = const Value.absent(),
    this.currentUnit = const Value.absent(),
    this.currentLesson = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
  }) : studentId = Value(studentId),
       topic = Value(topic),
       title = Value(title),
       description = Value(description);
  static Insertable<LearningPath> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? topic,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? unitsJson,
    Expression<int>? totalLessons,
    Expression<int>? completedLessons,
    Expression<int>? currentUnit,
    Expression<int>? currentLesson,
    Expression<DateTime>? generatedAt,
    Expression<DateTime>? lastAccessedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (topic != null) 'topic': topic,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (unitsJson != null) 'units_json': unitsJson,
      if (totalLessons != null) 'total_lessons': totalLessons,
      if (completedLessons != null) 'completed_lessons': completedLessons,
      if (currentUnit != null) 'current_unit': currentUnit,
      if (currentLesson != null) 'current_lesson': currentLesson,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
    });
  }

  LearningPathsCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? topic,
    Value<String>? title,
    Value<String>? description,
    Value<String>? unitsJson,
    Value<int>? totalLessons,
    Value<int>? completedLessons,
    Value<int>? currentUnit,
    Value<int>? currentLesson,
    Value<DateTime>? generatedAt,
    Value<DateTime>? lastAccessedAt,
  }) {
    return LearningPathsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      topic: topic ?? this.topic,
      title: title ?? this.title,
      description: description ?? this.description,
      unitsJson: unitsJson ?? this.unitsJson,
      totalLessons: totalLessons ?? this.totalLessons,
      completedLessons: completedLessons ?? this.completedLessons,
      currentUnit: currentUnit ?? this.currentUnit,
      currentLesson: currentLesson ?? this.currentLesson,
      generatedAt: generatedAt ?? this.generatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (unitsJson.present) {
      map['units_json'] = Variable<String>(unitsJson.value);
    }
    if (totalLessons.present) {
      map['total_lessons'] = Variable<int>(totalLessons.value);
    }
    if (completedLessons.present) {
      map['completed_lessons'] = Variable<int>(completedLessons.value);
    }
    if (currentUnit.present) {
      map['current_unit'] = Variable<int>(currentUnit.value);
    }
    if (currentLesson.present) {
      map['current_lesson'] = Variable<int>(currentLesson.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<DateTime>(generatedAt.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningPathsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('topic: $topic, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('unitsJson: $unitsJson, ')
          ..write('totalLessons: $totalLessons, ')
          ..write('completedLessons: $completedLessons, ')
          ..write('currentUnit: $currentUnit, ')
          ..write('currentLesson: $currentLesson, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt')
          ..write(')'))
        .toString();
  }
}

class $EarnedBadgesTable extends EarnedBadges
    with TableInfo<$EarnedBadgesTable, EarnedBadge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EarnedBadgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _badgeIdMeta = const VerificationMeta(
    'badgeId',
  );
  @override
  late final GeneratedColumn<String> badgeId = GeneratedColumn<String>(
    'badge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _badgeNameMeta = const VerificationMeta(
    'badgeName',
  );
  @override
  late final GeneratedColumn<String> badgeName = GeneratedColumn<String>(
    'badge_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _earnedAtMeta = const VerificationMeta(
    'earnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> earnedAt = GeneratedColumn<DateTime>(
    'earned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    badgeId,
    badgeName,
    earnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'earned_badges';
  @override
  VerificationContext validateIntegrity(
    Insertable<EarnedBadge> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('badge_id')) {
      context.handle(
        _badgeIdMeta,
        badgeId.isAcceptableOrUnknown(data['badge_id']!, _badgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_badgeIdMeta);
    }
    if (data.containsKey('badge_name')) {
      context.handle(
        _badgeNameMeta,
        badgeName.isAcceptableOrUnknown(data['badge_name']!, _badgeNameMeta),
      );
    } else if (isInserting) {
      context.missing(_badgeNameMeta);
    }
    if (data.containsKey('earned_at')) {
      context.handle(
        _earnedAtMeta,
        earnedAt.isAcceptableOrUnknown(data['earned_at']!, _earnedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {studentId, badgeId},
  ];
  @override
  EarnedBadge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EarnedBadge(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      badgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badge_id'],
      )!,
      badgeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badge_name'],
      )!,
      earnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}earned_at'],
      )!,
    );
  }

  @override
  $EarnedBadgesTable createAlias(String alias) {
    return $EarnedBadgesTable(attachedDatabase, alias);
  }
}

class EarnedBadge extends DataClass implements Insertable<EarnedBadge> {
  final int id;
  final int studentId;
  final String badgeId;
  final String badgeName;
  final DateTime earnedAt;
  const EarnedBadge({
    required this.id,
    required this.studentId,
    required this.badgeId,
    required this.badgeName,
    required this.earnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['badge_id'] = Variable<String>(badgeId);
    map['badge_name'] = Variable<String>(badgeName);
    map['earned_at'] = Variable<DateTime>(earnedAt);
    return map;
  }

  EarnedBadgesCompanion toCompanion(bool nullToAbsent) {
    return EarnedBadgesCompanion(
      id: Value(id),
      studentId: Value(studentId),
      badgeId: Value(badgeId),
      badgeName: Value(badgeName),
      earnedAt: Value(earnedAt),
    );
  }

  factory EarnedBadge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EarnedBadge(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      badgeId: serializer.fromJson<String>(json['badgeId']),
      badgeName: serializer.fromJson<String>(json['badgeName']),
      earnedAt: serializer.fromJson<DateTime>(json['earnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'badgeId': serializer.toJson<String>(badgeId),
      'badgeName': serializer.toJson<String>(badgeName),
      'earnedAt': serializer.toJson<DateTime>(earnedAt),
    };
  }

  EarnedBadge copyWith({
    int? id,
    int? studentId,
    String? badgeId,
    String? badgeName,
    DateTime? earnedAt,
  }) => EarnedBadge(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    badgeId: badgeId ?? this.badgeId,
    badgeName: badgeName ?? this.badgeName,
    earnedAt: earnedAt ?? this.earnedAt,
  );
  EarnedBadge copyWithCompanion(EarnedBadgesCompanion data) {
    return EarnedBadge(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      badgeId: data.badgeId.present ? data.badgeId.value : this.badgeId,
      badgeName: data.badgeName.present ? data.badgeName.value : this.badgeName,
      earnedAt: data.earnedAt.present ? data.earnedAt.value : this.earnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EarnedBadge(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('badgeId: $badgeId, ')
          ..write('badgeName: $badgeName, ')
          ..write('earnedAt: $earnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, studentId, badgeId, badgeName, earnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EarnedBadge &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.badgeId == this.badgeId &&
          other.badgeName == this.badgeName &&
          other.earnedAt == this.earnedAt);
}

class EarnedBadgesCompanion extends UpdateCompanion<EarnedBadge> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> badgeId;
  final Value<String> badgeName;
  final Value<DateTime> earnedAt;
  const EarnedBadgesCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.badgeId = const Value.absent(),
    this.badgeName = const Value.absent(),
    this.earnedAt = const Value.absent(),
  });
  EarnedBadgesCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String badgeId,
    required String badgeName,
    this.earnedAt = const Value.absent(),
  }) : studentId = Value(studentId),
       badgeId = Value(badgeId),
       badgeName = Value(badgeName);
  static Insertable<EarnedBadge> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? badgeId,
    Expression<String>? badgeName,
    Expression<DateTime>? earnedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (badgeId != null) 'badge_id': badgeId,
      if (badgeName != null) 'badge_name': badgeName,
      if (earnedAt != null) 'earned_at': earnedAt,
    });
  }

  EarnedBadgesCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? badgeId,
    Value<String>? badgeName,
    Value<DateTime>? earnedAt,
  }) {
    return EarnedBadgesCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      badgeId: badgeId ?? this.badgeId,
      badgeName: badgeName ?? this.badgeName,
      earnedAt: earnedAt ?? this.earnedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (badgeId.present) {
      map['badge_id'] = Variable<String>(badgeId.value);
    }
    if (badgeName.present) {
      map['badge_name'] = Variable<String>(badgeName.value);
    }
    if (earnedAt.present) {
      map['earned_at'] = Variable<DateTime>(earnedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EarnedBadgesCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('badgeId: $badgeId, ')
          ..write('badgeName: $badgeName, ')
          ..write('earnedAt: $earnedAt')
          ..write(')'))
        .toString();
  }
}

class $StudentProjectsTable extends StudentProjects
    with TableInfo<$StudentProjectsTable, StudentProject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudentProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectTypeMeta = const VerificationMeta(
    'projectType',
  );
  @override
  late final GeneratedColumn<String> projectType = GeneratedColumn<String>(
    'project_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepsJsonMeta = const VerificationMeta(
    'stepsJson',
  );
  @override
  late final GeneratedColumn<String> stepsJson = GeneratedColumn<String>(
    'steps_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('in_progress'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    title,
    topic,
    projectType,
    stepsJson,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'student_projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<StudentProject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('project_type')) {
      context.handle(
        _projectTypeMeta,
        projectType.isAcceptableOrUnknown(
          data['project_type']!,
          _projectTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_projectTypeMeta);
    }
    if (data.containsKey('steps_json')) {
      context.handle(
        _stepsJsonMeta,
        stepsJson.isAcceptableOrUnknown(data['steps_json']!, _stepsJsonMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StudentProject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudentProject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      projectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_type'],
      )!,
      stepsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steps_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StudentProjectsTable createAlias(String alias) {
    return $StudentProjectsTable(attachedDatabase, alias);
  }
}

class StudentProject extends DataClass implements Insertable<StudentProject> {
  final int id;
  final int studentId;
  final String title;
  final String topic;
  final String projectType;
  final String stepsJson;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const StudentProject({
    required this.id,
    required this.studentId,
    required this.title,
    required this.topic,
    required this.projectType,
    required this.stepsJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['title'] = Variable<String>(title);
    map['topic'] = Variable<String>(topic);
    map['project_type'] = Variable<String>(projectType);
    map['steps_json'] = Variable<String>(stepsJson);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StudentProjectsCompanion toCompanion(bool nullToAbsent) {
    return StudentProjectsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      title: Value(title),
      topic: Value(topic),
      projectType: Value(projectType),
      stepsJson: Value(stepsJson),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StudentProject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudentProject(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      title: serializer.fromJson<String>(json['title']),
      topic: serializer.fromJson<String>(json['topic']),
      projectType: serializer.fromJson<String>(json['projectType']),
      stepsJson: serializer.fromJson<String>(json['stepsJson']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'title': serializer.toJson<String>(title),
      'topic': serializer.toJson<String>(topic),
      'projectType': serializer.toJson<String>(projectType),
      'stepsJson': serializer.toJson<String>(stepsJson),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StudentProject copyWith({
    int? id,
    int? studentId,
    String? title,
    String? topic,
    String? projectType,
    String? stepsJson,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StudentProject(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    title: title ?? this.title,
    topic: topic ?? this.topic,
    projectType: projectType ?? this.projectType,
    stepsJson: stepsJson ?? this.stepsJson,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StudentProject copyWithCompanion(StudentProjectsCompanion data) {
    return StudentProject(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      title: data.title.present ? data.title.value : this.title,
      topic: data.topic.present ? data.topic.value : this.topic,
      projectType: data.projectType.present
          ? data.projectType.value
          : this.projectType,
      stepsJson: data.stepsJson.present ? data.stepsJson.value : this.stepsJson,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudentProject(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('title: $title, ')
          ..write('topic: $topic, ')
          ..write('projectType: $projectType, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    studentId,
    title,
    topic,
    projectType,
    stepsJson,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentProject &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.title == this.title &&
          other.topic == this.topic &&
          other.projectType == this.projectType &&
          other.stepsJson == this.stepsJson &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StudentProjectsCompanion extends UpdateCompanion<StudentProject> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> title;
  final Value<String> topic;
  final Value<String> projectType;
  final Value<String> stepsJson;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const StudentProjectsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.title = const Value.absent(),
    this.topic = const Value.absent(),
    this.projectType = const Value.absent(),
    this.stepsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  StudentProjectsCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String title,
    required String topic,
    required String projectType,
    this.stepsJson = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : studentId = Value(studentId),
       title = Value(title),
       topic = Value(topic),
       projectType = Value(projectType);
  static Insertable<StudentProject> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? title,
    Expression<String>? topic,
    Expression<String>? projectType,
    Expression<String>? stepsJson,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (title != null) 'title': title,
      if (topic != null) 'topic': topic,
      if (projectType != null) 'project_type': projectType,
      if (stepsJson != null) 'steps_json': stepsJson,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  StudentProjectsCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? title,
    Value<String>? topic,
    Value<String>? projectType,
    Value<String>? stepsJson,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return StudentProjectsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      projectType: projectType ?? this.projectType,
      stepsJson: stepsJson ?? this.stepsJson,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (projectType.present) {
      map['project_type'] = Variable<String>(projectType.value);
    }
    if (stepsJson.present) {
      map['steps_json'] = Variable<String>(stepsJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudentProjectsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('title: $title, ')
          ..write('topic: $topic, ')
          ..write('projectType: $projectType, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WebsiteProjectsTable extends WebsiteProjects
    with TableInfo<$WebsiteProjectsTable, WebsiteProject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WebsiteProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _studentIdMeta = const VerificationMeta(
    'studentId',
  );
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
    'student_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _themeColorMeta = const VerificationMeta(
    'themeColor',
  );
  @override
  late final GeneratedColumn<String> themeColor = GeneratedColumn<String>(
    'theme_color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#4F46E5'),
  );
  static const VerificationMeta _blocksJsonMeta = const VerificationMeta(
    'blocksJson',
  );
  @override
  late final GeneratedColumn<String> blocksJson = GeneratedColumn<String>(
    'blocks_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studentId,
    title,
    themeColor,
    blocksJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'website_projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<WebsiteProject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(
        _studentIdMeta,
        studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('theme_color')) {
      context.handle(
        _themeColorMeta,
        themeColor.isAcceptableOrUnknown(data['theme_color']!, _themeColorMeta),
      );
    }
    if (data.containsKey('blocks_json')) {
      context.handle(
        _blocksJsonMeta,
        blocksJson.isAcceptableOrUnknown(data['blocks_json']!, _blocksJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WebsiteProject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WebsiteProject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}student_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      themeColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_color'],
      )!,
      blocksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocks_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WebsiteProjectsTable createAlias(String alias) {
    return $WebsiteProjectsTable(attachedDatabase, alias);
  }
}

class WebsiteProject extends DataClass implements Insertable<WebsiteProject> {
  final int id;
  final int studentId;
  final String title;
  final String themeColor;
  final String blocksJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const WebsiteProject({
    required this.id,
    required this.studentId,
    required this.title,
    required this.themeColor,
    required this.blocksJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['title'] = Variable<String>(title);
    map['theme_color'] = Variable<String>(themeColor);
    map['blocks_json'] = Variable<String>(blocksJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WebsiteProjectsCompanion toCompanion(bool nullToAbsent) {
    return WebsiteProjectsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      title: Value(title),
      themeColor: Value(themeColor),
      blocksJson: Value(blocksJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WebsiteProject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WebsiteProject(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      title: serializer.fromJson<String>(json['title']),
      themeColor: serializer.fromJson<String>(json['themeColor']),
      blocksJson: serializer.fromJson<String>(json['blocksJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'title': serializer.toJson<String>(title),
      'themeColor': serializer.toJson<String>(themeColor),
      'blocksJson': serializer.toJson<String>(blocksJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WebsiteProject copyWith({
    int? id,
    int? studentId,
    String? title,
    String? themeColor,
    String? blocksJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WebsiteProject(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    title: title ?? this.title,
    themeColor: themeColor ?? this.themeColor,
    blocksJson: blocksJson ?? this.blocksJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WebsiteProject copyWithCompanion(WebsiteProjectsCompanion data) {
    return WebsiteProject(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      title: data.title.present ? data.title.value : this.title,
      themeColor: data.themeColor.present
          ? data.themeColor.value
          : this.themeColor,
      blocksJson: data.blocksJson.present
          ? data.blocksJson.value
          : this.blocksJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WebsiteProject(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('title: $title, ')
          ..write('themeColor: $themeColor, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    studentId,
    title,
    themeColor,
    blocksJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WebsiteProject &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.title == this.title &&
          other.themeColor == this.themeColor &&
          other.blocksJson == this.blocksJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WebsiteProjectsCompanion extends UpdateCompanion<WebsiteProject> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<String> title;
  final Value<String> themeColor;
  final Value<String> blocksJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const WebsiteProjectsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.title = const Value.absent(),
    this.themeColor = const Value.absent(),
    this.blocksJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WebsiteProjectsCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required String title,
    this.themeColor = const Value.absent(),
    this.blocksJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : studentId = Value(studentId),
       title = Value(title);
  static Insertable<WebsiteProject> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<String>? title,
    Expression<String>? themeColor,
    Expression<String>? blocksJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (title != null) 'title': title,
      if (themeColor != null) 'theme_color': themeColor,
      if (blocksJson != null) 'blocks_json': blocksJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WebsiteProjectsCompanion copyWith({
    Value<int>? id,
    Value<int>? studentId,
    Value<String>? title,
    Value<String>? themeColor,
    Value<String>? blocksJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return WebsiteProjectsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      title: title ?? this.title,
      themeColor: themeColor ?? this.themeColor,
      blocksJson: blocksJson ?? this.blocksJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (themeColor.present) {
      map['theme_color'] = Variable<String>(themeColor.value);
    }
    if (blocksJson.present) {
      map['blocks_json'] = Variable<String>(blocksJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WebsiteProjectsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('title: $title, ')
          ..write('themeColor: $themeColor, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TranslationCacheEntriesTable extends TranslationCacheEntries
    with TableInfo<$TranslationCacheEntriesTable, TranslationCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TranslationCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _langCodeMeta = const VerificationMeta(
    'langCode',
  );
  @override
  late final GeneratedColumn<String> langCode = GeneratedColumn<String>(
    'lang_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelTagMeta = const VerificationMeta(
    'modelTag',
  );
  @override
  late final GeneratedColumn<String> modelTag = GeneratedColumn<String>(
    'model_tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTextMeta = const VerificationMeta(
    'sourceText',
  );
  @override
  late final GeneratedColumn<String> sourceText = GeneratedColumn<String>(
    'source_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _translatedTextMeta = const VerificationMeta(
    'translatedText',
  );
  @override
  late final GeneratedColumn<String> translatedText = GeneratedColumn<String>(
    'translated_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta(
    'useCount',
  );
  @override
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cacheKey,
    langCode,
    direction,
    modelTag,
    sourceText,
    translatedText,
    useCount,
    lastUsedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'translation_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TranslationCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('lang_code')) {
      context.handle(
        _langCodeMeta,
        langCode.isAcceptableOrUnknown(data['lang_code']!, _langCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_langCodeMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('model_tag')) {
      context.handle(
        _modelTagMeta,
        modelTag.isAcceptableOrUnknown(data['model_tag']!, _modelTagMeta),
      );
    } else if (isInserting) {
      context.missing(_modelTagMeta);
    }
    if (data.containsKey('source_text')) {
      context.handle(
        _sourceTextMeta,
        sourceText.isAcceptableOrUnknown(data['source_text']!, _sourceTextMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTextMeta);
    }
    if (data.containsKey('translated_text')) {
      context.handle(
        _translatedTextMeta,
        translatedText.isAcceptableOrUnknown(
          data['translated_text']!,
          _translatedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_translatedTextMeta);
    }
    if (data.containsKey('use_count')) {
      context.handle(
        _useCountMeta,
        useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TranslationCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TranslationCacheEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      langCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lang_code'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      modelTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_tag'],
      )!,
      sourceText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_text'],
      )!,
      translatedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}translated_text'],
      )!,
      useCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_count'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TranslationCacheEntriesTable createAlias(String alias) {
    return $TranslationCacheEntriesTable(attachedDatabase, alias);
  }
}

class TranslationCacheEntry extends DataClass
    implements Insertable<TranslationCacheEntry> {
  final int id;

  /// `sha256(modelTag|direction|langCode|normalizedSource)`, unique.
  /// Looked up directly — see TranslationCacheDao.lookup.
  final String cacheKey;

  /// BCP-47 code of the non-English side of the pair.
  final String langCode;

  /// `to_en` or `from_en`.
  final String direction;

  /// Identifies the model file that produced this row. Re-quantizing the
  /// GGUF (tools/quantize_translate_model.ps1 can emit Q4_K_M, Q4_0, …)
  /// changes what the model outputs, so entries from the previous file must
  /// not be served for the new one. Included in [cacheKey] rather than
  /// checked separately, so a model swap misses instead of matching.
  final String modelTag;

  /// Kept in full so a hit can be verified against the key rather than
  /// trusted blindly — a hash collision would otherwise show the student
  /// someone else's sentence.
  final String sourceText;
  final String translatedText;
  final int useCount;
  final DateTime lastUsedAt;
  final DateTime createdAt;
  const TranslationCacheEntry({
    required this.id,
    required this.cacheKey,
    required this.langCode,
    required this.direction,
    required this.modelTag,
    required this.sourceText,
    required this.translatedText,
    required this.useCount,
    required this.lastUsedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cache_key'] = Variable<String>(cacheKey);
    map['lang_code'] = Variable<String>(langCode);
    map['direction'] = Variable<String>(direction);
    map['model_tag'] = Variable<String>(modelTag);
    map['source_text'] = Variable<String>(sourceText);
    map['translated_text'] = Variable<String>(translatedText);
    map['use_count'] = Variable<int>(useCount);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TranslationCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return TranslationCacheEntriesCompanion(
      id: Value(id),
      cacheKey: Value(cacheKey),
      langCode: Value(langCode),
      direction: Value(direction),
      modelTag: Value(modelTag),
      sourceText: Value(sourceText),
      translatedText: Value(translatedText),
      useCount: Value(useCount),
      lastUsedAt: Value(lastUsedAt),
      createdAt: Value(createdAt),
    );
  }

  factory TranslationCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TranslationCacheEntry(
      id: serializer.fromJson<int>(json['id']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      langCode: serializer.fromJson<String>(json['langCode']),
      direction: serializer.fromJson<String>(json['direction']),
      modelTag: serializer.fromJson<String>(json['modelTag']),
      sourceText: serializer.fromJson<String>(json['sourceText']),
      translatedText: serializer.fromJson<String>(json['translatedText']),
      useCount: serializer.fromJson<int>(json['useCount']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'langCode': serializer.toJson<String>(langCode),
      'direction': serializer.toJson<String>(direction),
      'modelTag': serializer.toJson<String>(modelTag),
      'sourceText': serializer.toJson<String>(sourceText),
      'translatedText': serializer.toJson<String>(translatedText),
      'useCount': serializer.toJson<int>(useCount),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TranslationCacheEntry copyWith({
    int? id,
    String? cacheKey,
    String? langCode,
    String? direction,
    String? modelTag,
    String? sourceText,
    String? translatedText,
    int? useCount,
    DateTime? lastUsedAt,
    DateTime? createdAt,
  }) => TranslationCacheEntry(
    id: id ?? this.id,
    cacheKey: cacheKey ?? this.cacheKey,
    langCode: langCode ?? this.langCode,
    direction: direction ?? this.direction,
    modelTag: modelTag ?? this.modelTag,
    sourceText: sourceText ?? this.sourceText,
    translatedText: translatedText ?? this.translatedText,
    useCount: useCount ?? this.useCount,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  TranslationCacheEntry copyWithCompanion(
    TranslationCacheEntriesCompanion data,
  ) {
    return TranslationCacheEntry(
      id: data.id.present ? data.id.value : this.id,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      langCode: data.langCode.present ? data.langCode.value : this.langCode,
      direction: data.direction.present ? data.direction.value : this.direction,
      modelTag: data.modelTag.present ? data.modelTag.value : this.modelTag,
      sourceText: data.sourceText.present
          ? data.sourceText.value
          : this.sourceText,
      translatedText: data.translatedText.present
          ? data.translatedText.value
          : this.translatedText,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TranslationCacheEntry(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('langCode: $langCode, ')
          ..write('direction: $direction, ')
          ..write('modelTag: $modelTag, ')
          ..write('sourceText: $sourceText, ')
          ..write('translatedText: $translatedText, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cacheKey,
    langCode,
    direction,
    modelTag,
    sourceText,
    translatedText,
    useCount,
    lastUsedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranslationCacheEntry &&
          other.id == this.id &&
          other.cacheKey == this.cacheKey &&
          other.langCode == this.langCode &&
          other.direction == this.direction &&
          other.modelTag == this.modelTag &&
          other.sourceText == this.sourceText &&
          other.translatedText == this.translatedText &&
          other.useCount == this.useCount &&
          other.lastUsedAt == this.lastUsedAt &&
          other.createdAt == this.createdAt);
}

class TranslationCacheEntriesCompanion
    extends UpdateCompanion<TranslationCacheEntry> {
  final Value<int> id;
  final Value<String> cacheKey;
  final Value<String> langCode;
  final Value<String> direction;
  final Value<String> modelTag;
  final Value<String> sourceText;
  final Value<String> translatedText;
  final Value<int> useCount;
  final Value<DateTime> lastUsedAt;
  final Value<DateTime> createdAt;
  const TranslationCacheEntriesCompanion({
    this.id = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.langCode = const Value.absent(),
    this.direction = const Value.absent(),
    this.modelTag = const Value.absent(),
    this.sourceText = const Value.absent(),
    this.translatedText = const Value.absent(),
    this.useCount = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TranslationCacheEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String cacheKey,
    required String langCode,
    required String direction,
    required String modelTag,
    required String sourceText,
    required String translatedText,
    this.useCount = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       langCode = Value(langCode),
       direction = Value(direction),
       modelTag = Value(modelTag),
       sourceText = Value(sourceText),
       translatedText = Value(translatedText);
  static Insertable<TranslationCacheEntry> custom({
    Expression<int>? id,
    Expression<String>? cacheKey,
    Expression<String>? langCode,
    Expression<String>? direction,
    Expression<String>? modelTag,
    Expression<String>? sourceText,
    Expression<String>? translatedText,
    Expression<int>? useCount,
    Expression<DateTime>? lastUsedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (langCode != null) 'lang_code': langCode,
      if (direction != null) 'direction': direction,
      if (modelTag != null) 'model_tag': modelTag,
      if (sourceText != null) 'source_text': sourceText,
      if (translatedText != null) 'translated_text': translatedText,
      if (useCount != null) 'use_count': useCount,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TranslationCacheEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? cacheKey,
    Value<String>? langCode,
    Value<String>? direction,
    Value<String>? modelTag,
    Value<String>? sourceText,
    Value<String>? translatedText,
    Value<int>? useCount,
    Value<DateTime>? lastUsedAt,
    Value<DateTime>? createdAt,
  }) {
    return TranslationCacheEntriesCompanion(
      id: id ?? this.id,
      cacheKey: cacheKey ?? this.cacheKey,
      langCode: langCode ?? this.langCode,
      direction: direction ?? this.direction,
      modelTag: modelTag ?? this.modelTag,
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      useCount: useCount ?? this.useCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (langCode.present) {
      map['lang_code'] = Variable<String>(langCode.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (modelTag.present) {
      map['model_tag'] = Variable<String>(modelTag.value);
    }
    if (sourceText.present) {
      map['source_text'] = Variable<String>(sourceText.value);
    }
    if (translatedText.present) {
      map['translated_text'] = Variable<String>(translatedText.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranslationCacheEntriesCompanion(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('langCode: $langCode, ')
          ..write('direction: $direction, ')
          ..write('modelTag: $modelTag, ')
          ..write('sourceText: $sourceText, ')
          ..write('translatedText: $translatedText, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TopicResourcesTable extends TopicResources
    with TableInfo<$TopicResourcesTable, TopicResource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TopicResourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicKeyMeta = const VerificationMeta(
    'topicKey',
  );
  @override
  late final GeneratedColumn<String> topicKey = GeneratedColumn<String>(
    'topic_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _termMarkerMeta = const VerificationMeta(
    'termMarker',
  );
  @override
  late final GeneratedColumn<int> termMarker = GeneratedColumn<int>(
    'term_marker',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(kAllTermsMarker),
  );
  static const VerificationMeta _resourceTitleMeta = const VerificationMeta(
    'resourceTitle',
  );
  @override
  late final GeneratedColumn<String> resourceTitle = GeneratedColumn<String>(
    'resource_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentChunkMeta = const VerificationMeta(
    'contentChunk',
  );
  @override
  late final GeneratedColumn<String> contentChunk = GeneratedColumn<String>(
    'content_chunk',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    topicKey,
    termMarker,
    resourceTitle,
    contentChunk,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'topic_resources';
  @override
  VerificationContext validateIntegrity(
    Insertable<TopicResource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('topic_key')) {
      context.handle(
        _topicKeyMeta,
        topicKey.isAcceptableOrUnknown(data['topic_key']!, _topicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_topicKeyMeta);
    }
    if (data.containsKey('term_marker')) {
      context.handle(
        _termMarkerMeta,
        termMarker.isAcceptableOrUnknown(data['term_marker']!, _termMarkerMeta),
      );
    }
    if (data.containsKey('resource_title')) {
      context.handle(
        _resourceTitleMeta,
        resourceTitle.isAcceptableOrUnknown(
          data['resource_title']!,
          _resourceTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resourceTitleMeta);
    }
    if (data.containsKey('content_chunk')) {
      context.handle(
        _contentChunkMeta,
        contentChunk.isAcceptableOrUnknown(
          data['content_chunk']!,
          _contentChunkMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentChunkMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TopicResource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TopicResource(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      topicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_key'],
      )!,
      termMarker: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}term_marker'],
      )!,
      resourceTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_title'],
      )!,
      contentChunk: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_chunk'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TopicResourcesTable createAlias(String alias) {
    return $TopicResourcesTable(attachedDatabase, alias);
  }
}

class TopicResource extends DataClass implements Insertable<TopicResource> {
  final int id;

  /// Curriculum subject this resource belongs to, e.g. `chemistry`.
  ///
  /// Must be spelled the same way on write and on read or retrieval silently
  /// returns nothing forever — see `normalizeSubjectId`, which both sides call.
  final String subjectId;

  /// Normalized lesson/topic identifier tying the resource to one point in the
  /// hardcoded syllabus. Always written through `normalizeTopicKey` so a
  /// teacher typing "Acid–Base Balances" and a chat turn on the lesson titled
  /// "Acid-Base Balances" land on the same key.
  final String topicKey;

  /// School term this resource applies to: 1, 2 or 3.
  ///
  /// [kAllTermsMarker] (0) means "applies to every term", which is the right
  /// default for a textbook extract that is not term-specific.
  final int termMarker;

  /// Human-readable name, e.g. "Acid-Base Balances Notes". Every chunk of one
  /// document shares the title — that is what makes deletion by title able to
  /// remove a whole resource in a single statement.
  final String resourceTitle;

  /// One ~500-character slice of the resource's text. Stored as many small
  /// rows rather than one large blob so a retrieval can return the paragraphs
  /// that matter instead of a whole chapter — on a 4 GB device the prompt
  /// budget, not the disk, is the scarce resource.
  final String contentChunk;

  /// ISO-8601 UTC timestamp. TEXT rather than drift's default integer
  /// `DateTimeColumn` so the physical column type matches the agreed schema.
  final String createdAt;
  const TopicResource({
    required this.id,
    required this.subjectId,
    required this.topicKey,
    required this.termMarker,
    required this.resourceTitle,
    required this.contentChunk,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['topic_key'] = Variable<String>(topicKey);
    map['term_marker'] = Variable<int>(termMarker);
    map['resource_title'] = Variable<String>(resourceTitle);
    map['content_chunk'] = Variable<String>(contentChunk);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  TopicResourcesCompanion toCompanion(bool nullToAbsent) {
    return TopicResourcesCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      topicKey: Value(topicKey),
      termMarker: Value(termMarker),
      resourceTitle: Value(resourceTitle),
      contentChunk: Value(contentChunk),
      createdAt: Value(createdAt),
    );
  }

  factory TopicResource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TopicResource(
      id: serializer.fromJson<int>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      topicKey: serializer.fromJson<String>(json['topicKey']),
      termMarker: serializer.fromJson<int>(json['termMarker']),
      resourceTitle: serializer.fromJson<String>(json['resourceTitle']),
      contentChunk: serializer.fromJson<String>(json['contentChunk']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'topicKey': serializer.toJson<String>(topicKey),
      'termMarker': serializer.toJson<int>(termMarker),
      'resourceTitle': serializer.toJson<String>(resourceTitle),
      'contentChunk': serializer.toJson<String>(contentChunk),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  TopicResource copyWith({
    int? id,
    String? subjectId,
    String? topicKey,
    int? termMarker,
    String? resourceTitle,
    String? contentChunk,
    String? createdAt,
  }) => TopicResource(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    topicKey: topicKey ?? this.topicKey,
    termMarker: termMarker ?? this.termMarker,
    resourceTitle: resourceTitle ?? this.resourceTitle,
    contentChunk: contentChunk ?? this.contentChunk,
    createdAt: createdAt ?? this.createdAt,
  );
  TopicResource copyWithCompanion(TopicResourcesCompanion data) {
    return TopicResource(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      topicKey: data.topicKey.present ? data.topicKey.value : this.topicKey,
      termMarker: data.termMarker.present
          ? data.termMarker.value
          : this.termMarker,
      resourceTitle: data.resourceTitle.present
          ? data.resourceTitle.value
          : this.resourceTitle,
      contentChunk: data.contentChunk.present
          ? data.contentChunk.value
          : this.contentChunk,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TopicResource(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('topicKey: $topicKey, ')
          ..write('termMarker: $termMarker, ')
          ..write('resourceTitle: $resourceTitle, ')
          ..write('contentChunk: $contentChunk, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subjectId,
    topicKey,
    termMarker,
    resourceTitle,
    contentChunk,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TopicResource &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.topicKey == this.topicKey &&
          other.termMarker == this.termMarker &&
          other.resourceTitle == this.resourceTitle &&
          other.contentChunk == this.contentChunk &&
          other.createdAt == this.createdAt);
}

class TopicResourcesCompanion extends UpdateCompanion<TopicResource> {
  final Value<int> id;
  final Value<String> subjectId;
  final Value<String> topicKey;
  final Value<int> termMarker;
  final Value<String> resourceTitle;
  final Value<String> contentChunk;
  final Value<String> createdAt;
  const TopicResourcesCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.topicKey = const Value.absent(),
    this.termMarker = const Value.absent(),
    this.resourceTitle = const Value.absent(),
    this.contentChunk = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TopicResourcesCompanion.insert({
    this.id = const Value.absent(),
    required String subjectId,
    required String topicKey,
    this.termMarker = const Value.absent(),
    required String resourceTitle,
    required String contentChunk,
    required String createdAt,
  }) : subjectId = Value(subjectId),
       topicKey = Value(topicKey),
       resourceTitle = Value(resourceTitle),
       contentChunk = Value(contentChunk),
       createdAt = Value(createdAt);
  static Insertable<TopicResource> custom({
    Expression<int>? id,
    Expression<String>? subjectId,
    Expression<String>? topicKey,
    Expression<int>? termMarker,
    Expression<String>? resourceTitle,
    Expression<String>? contentChunk,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (topicKey != null) 'topic_key': topicKey,
      if (termMarker != null) 'term_marker': termMarker,
      if (resourceTitle != null) 'resource_title': resourceTitle,
      if (contentChunk != null) 'content_chunk': contentChunk,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TopicResourcesCompanion copyWith({
    Value<int>? id,
    Value<String>? subjectId,
    Value<String>? topicKey,
    Value<int>? termMarker,
    Value<String>? resourceTitle,
    Value<String>? contentChunk,
    Value<String>? createdAt,
  }) {
    return TopicResourcesCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      topicKey: topicKey ?? this.topicKey,
      termMarker: termMarker ?? this.termMarker,
      resourceTitle: resourceTitle ?? this.resourceTitle,
      contentChunk: contentChunk ?? this.contentChunk,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (topicKey.present) {
      map['topic_key'] = Variable<String>(topicKey.value);
    }
    if (termMarker.present) {
      map['term_marker'] = Variable<int>(termMarker.value);
    }
    if (resourceTitle.present) {
      map['resource_title'] = Variable<String>(resourceTitle.value);
    }
    if (contentChunk.present) {
      map['content_chunk'] = Variable<String>(contentChunk.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TopicResourcesCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('topicKey: $topicKey, ')
          ..write('termMarker: $termMarker, ')
          ..write('resourceTitle: $resourceTitle, ')
          ..write('contentChunk: $contentChunk, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CustomSubjectsTable extends CustomSubjects
    with TableInfo<$CustomSubjectsTable, CustomSubject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomSubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('menu_book'),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#4F46E5'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    name,
    icon,
    color,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_subjects';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomSubject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomSubject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomSubject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CustomSubjectsTable createAlias(String alias) {
    return $CustomSubjectsTable(attachedDatabase, alias);
  }
}

class CustomSubject extends DataClass implements Insertable<CustomSubject> {
  final int id;

  /// Slug used in routes and as `topic_resources.subject_id`.
  ///
  /// Unique, and validated against the bundled ids before insert so a teacher
  /// cannot create a second "chemistry" that shadows the bundled one — see
  /// [CustomSubjectService.create].
  final String subjectId;

  /// What the teacher typed, shown on the subject card.
  final String name;

  /// Icon key and card colour, using the same vocabulary as the bundled
  /// curriculum JSON so one card widget renders both kinds.
  final String icon;
  final String color;

  /// ISO-8601 UTC, matching `topic_resources.created_at`.
  final String createdAt;
  const CustomSubject({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.icon,
    required this.color,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<String>(color);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  CustomSubjectsCompanion toCompanion(bool nullToAbsent) {
    return CustomSubjectsCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      createdAt: Value(createdAt),
    );
  }

  factory CustomSubject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomSubject(
      id: serializer.fromJson<int>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<String>(json['color']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<String>(color),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  CustomSubject copyWith({
    int? id,
    String? subjectId,
    String? name,
    String? icon,
    String? color,
    String? createdAt,
  }) => CustomSubject(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
  );
  CustomSubject copyWithCompanion(CustomSubjectsCompanion data) {
    return CustomSubject(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomSubject(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, subjectId, name, icon, color, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomSubject &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.createdAt == this.createdAt);
}

class CustomSubjectsCompanion extends UpdateCompanion<CustomSubject> {
  final Value<int> id;
  final Value<String> subjectId;
  final Value<String> name;
  final Value<String> icon;
  final Value<String> color;
  final Value<String> createdAt;
  const CustomSubjectsCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CustomSubjectsCompanion.insert({
    this.id = const Value.absent(),
    required String subjectId,
    required String name,
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    required String createdAt,
  }) : subjectId = Value(subjectId),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<CustomSubject> custom({
    Expression<int>? id,
    Expression<String>? subjectId,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CustomSubjectsCompanion copyWith({
    Value<int>? id,
    Value<String>? subjectId,
    Value<String>? name,
    Value<String>? icon,
    Value<String>? color,
    Value<String>? createdAt,
  }) {
    return CustomSubjectsCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomSubjectsCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$OticDatabase extends GeneratedDatabase {
  _$OticDatabase(QueryExecutor e) : super(e);
  $OticDatabaseManager get managers => $OticDatabaseManager(this);
  late final $StudentsTable students = $StudentsTable(this);
  late final $SessionSummariesTable sessionSummaries = $SessionSummariesTable(
    this,
  );
  late final $TopicProgressTable topicProgress = $TopicProgressTable(this);
  late final $LearningPathsTable learningPaths = $LearningPathsTable(this);
  late final $EarnedBadgesTable earnedBadges = $EarnedBadgesTable(this);
  late final $StudentProjectsTable studentProjects = $StudentProjectsTable(
    this,
  );
  late final $WebsiteProjectsTable websiteProjects = $WebsiteProjectsTable(
    this,
  );
  late final $TranslationCacheEntriesTable translationCacheEntries =
      $TranslationCacheEntriesTable(this);
  late final $TopicResourcesTable topicResources = $TopicResourcesTable(this);
  late final $CustomSubjectsTable customSubjects = $CustomSubjectsTable(this);
  late final Index idxTopicResourcesLookup = Index(
    'idx_topic_resources_lookup',
    'CREATE INDEX idx_topic_resources_lookup ON topic_resources (subject_id, topic_key)',
  );
  late final Index idxTopicResourcesTitle = Index(
    'idx_topic_resources_title',
    'CREATE INDEX idx_topic_resources_title ON topic_resources (resource_title)',
  );
  late final Index idxCustomSubjectsSubjectId = Index(
    'idx_custom_subjects_subject_id',
    'CREATE INDEX idx_custom_subjects_subject_id ON custom_subjects (subject_id)',
  );
  late final StudentDao studentDao = StudentDao(this as OticDatabase);
  late final SessionDao sessionDao = SessionDao(this as OticDatabase);
  late final PathDao pathDao = PathDao(this as OticDatabase);
  late final BadgeDao badgeDao = BadgeDao(this as OticDatabase);
  late final ProjectDao projectDao = ProjectDao(this as OticDatabase);
  late final WebsiteDao websiteDao = WebsiteDao(this as OticDatabase);
  late final TranslationCacheDao translationCacheDao = TranslationCacheDao(
    this as OticDatabase,
  );
  late final TopicResourceDao topicResourceDao = TopicResourceDao(
    this as OticDatabase,
  );
  late final CustomSubjectDao customSubjectDao = CustomSubjectDao(
    this as OticDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    students,
    sessionSummaries,
    topicProgress,
    learningPaths,
    earnedBadges,
    studentProjects,
    websiteProjects,
    translationCacheEntries,
    topicResources,
    customSubjects,
    idxTopicResourcesLookup,
    idxTopicResourcesTitle,
    idxCustomSubjectsSubjectId,
  ];
}

typedef $$StudentsTableCreateCompanionBuilder =
    StudentsCompanion Function({
      Value<int> id,
      required String name,
      Value<int?> age,
      Value<String?> grade,
      Value<String> language,
      Value<String> interestsJson,
      Value<String> learningStyle,
      Value<String> strengthsJson,
      Value<String> weaknessesJson,
      Value<String> goalsJson,
      Value<int> streakDays,
      Value<DateTime?> lastStreakDate,
      Value<int> totalPoints,
      Value<DateTime> createdAt,
      Value<DateTime> lastActiveAt,
    });
typedef $$StudentsTableUpdateCompanionBuilder =
    StudentsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int?> age,
      Value<String?> grade,
      Value<String> language,
      Value<String> interestsJson,
      Value<String> learningStyle,
      Value<String> strengthsJson,
      Value<String> weaknessesJson,
      Value<String> goalsJson,
      Value<int> streakDays,
      Value<DateTime?> lastStreakDate,
      Value<int> totalPoints,
      Value<DateTime> createdAt,
      Value<DateTime> lastActiveAt,
    });

class $$StudentsTableFilterComposer
    extends Composer<_$OticDatabase, $StudentsTable> {
  $$StudentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get interestsJson => $composableBuilder(
    column: $table.interestsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get learningStyle => $composableBuilder(
    column: $table.learningStyle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalsJson => $composableBuilder(
    column: $table.goalsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get streakDays => $composableBuilder(
    column: $table.streakDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastStreakDate => $composableBuilder(
    column: $table.lastStreakDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastActiveAt => $composableBuilder(
    column: $table.lastActiveAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StudentsTableOrderingComposer
    extends Composer<_$OticDatabase, $StudentsTable> {
  $$StudentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grade => $composableBuilder(
    column: $table.grade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interestsJson => $composableBuilder(
    column: $table.interestsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get learningStyle => $composableBuilder(
    column: $table.learningStyle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalsJson => $composableBuilder(
    column: $table.goalsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get streakDays => $composableBuilder(
    column: $table.streakDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastStreakDate => $composableBuilder(
    column: $table.lastStreakDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastActiveAt => $composableBuilder(
    column: $table.lastActiveAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StudentsTableAnnotationComposer
    extends Composer<_$OticDatabase, $StudentsTable> {
  $$StudentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get age =>
      $composableBuilder(column: $table.age, builder: (column) => column);

  GeneratedColumn<String> get grade =>
      $composableBuilder(column: $table.grade, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get interestsJson => $composableBuilder(
    column: $table.interestsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get learningStyle => $composableBuilder(
    column: $table.learningStyle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get goalsJson =>
      $composableBuilder(column: $table.goalsJson, builder: (column) => column);

  GeneratedColumn<int> get streakDays => $composableBuilder(
    column: $table.streakDays,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastStreakDate => $composableBuilder(
    column: $table.lastStreakDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPoints => $composableBuilder(
    column: $table.totalPoints,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastActiveAt => $composableBuilder(
    column: $table.lastActiveAt,
    builder: (column) => column,
  );
}

class $$StudentsTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $StudentsTable,
          Student,
          $$StudentsTableFilterComposer,
          $$StudentsTableOrderingComposer,
          $$StudentsTableAnnotationComposer,
          $$StudentsTableCreateCompanionBuilder,
          $$StudentsTableUpdateCompanionBuilder,
          (Student, BaseReferences<_$OticDatabase, $StudentsTable, Student>),
          Student,
          PrefetchHooks Function()
        > {
  $$StudentsTableTableManager(_$OticDatabase db, $StudentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StudentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> age = const Value.absent(),
                Value<String?> grade = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> interestsJson = const Value.absent(),
                Value<String> learningStyle = const Value.absent(),
                Value<String> strengthsJson = const Value.absent(),
                Value<String> weaknessesJson = const Value.absent(),
                Value<String> goalsJson = const Value.absent(),
                Value<int> streakDays = const Value.absent(),
                Value<DateTime?> lastStreakDate = const Value.absent(),
                Value<int> totalPoints = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastActiveAt = const Value.absent(),
              }) => StudentsCompanion(
                id: id,
                name: name,
                age: age,
                grade: grade,
                language: language,
                interestsJson: interestsJson,
                learningStyle: learningStyle,
                strengthsJson: strengthsJson,
                weaknessesJson: weaknessesJson,
                goalsJson: goalsJson,
                streakDays: streakDays,
                lastStreakDate: lastStreakDate,
                totalPoints: totalPoints,
                createdAt: createdAt,
                lastActiveAt: lastActiveAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<int?> age = const Value.absent(),
                Value<String?> grade = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> interestsJson = const Value.absent(),
                Value<String> learningStyle = const Value.absent(),
                Value<String> strengthsJson = const Value.absent(),
                Value<String> weaknessesJson = const Value.absent(),
                Value<String> goalsJson = const Value.absent(),
                Value<int> streakDays = const Value.absent(),
                Value<DateTime?> lastStreakDate = const Value.absent(),
                Value<int> totalPoints = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastActiveAt = const Value.absent(),
              }) => StudentsCompanion.insert(
                id: id,
                name: name,
                age: age,
                grade: grade,
                language: language,
                interestsJson: interestsJson,
                learningStyle: learningStyle,
                strengthsJson: strengthsJson,
                weaknessesJson: weaknessesJson,
                goalsJson: goalsJson,
                streakDays: streakDays,
                lastStreakDate: lastStreakDate,
                totalPoints: totalPoints,
                createdAt: createdAt,
                lastActiveAt: lastActiveAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StudentsTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $StudentsTable,
      Student,
      $$StudentsTableFilterComposer,
      $$StudentsTableOrderingComposer,
      $$StudentsTableAnnotationComposer,
      $$StudentsTableCreateCompanionBuilder,
      $$StudentsTableUpdateCompanionBuilder,
      (Student, BaseReferences<_$OticDatabase, $StudentsTable, Student>),
      Student,
      PrefetchHooks Function()
    >;
typedef $$SessionSummariesTableCreateCompanionBuilder =
    SessionSummariesCompanion Function({
      Value<int> id,
      required int studentId,
      required String topic,
      required String summary,
      Value<String> strengthsJson,
      Value<String> weaknessesJson,
      Value<String> highestStage,
      Value<int> messageCount,
      Value<DateTime> sessionAt,
    });
typedef $$SessionSummariesTableUpdateCompanionBuilder =
    SessionSummariesCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> topic,
      Value<String> summary,
      Value<String> strengthsJson,
      Value<String> weaknessesJson,
      Value<String> highestStage,
      Value<int> messageCount,
      Value<DateTime> sessionAt,
    });

class $$SessionSummariesTableFilterComposer
    extends Composer<_$OticDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get highestStage => $composableBuilder(
    column: $table.highestStage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sessionAt => $composableBuilder(
    column: $table.sessionAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionSummariesTableOrderingComposer
    extends Composer<_$OticDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get highestStage => $composableBuilder(
    column: $table.highestStage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sessionAt => $composableBuilder(
    column: $table.sessionAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionSummariesTableAnnotationComposer
    extends Composer<_$OticDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get strengthsJson => $composableBuilder(
    column: $table.strengthsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weaknessesJson => $composableBuilder(
    column: $table.weaknessesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get highestStage => $composableBuilder(
    column: $table.highestStage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sessionAt =>
      $composableBuilder(column: $table.sessionAt, builder: (column) => column);
}

class $$SessionSummariesTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $SessionSummariesTable,
          SessionSummary,
          $$SessionSummariesTableFilterComposer,
          $$SessionSummariesTableOrderingComposer,
          $$SessionSummariesTableAnnotationComposer,
          $$SessionSummariesTableCreateCompanionBuilder,
          $$SessionSummariesTableUpdateCompanionBuilder,
          (
            SessionSummary,
            BaseReferences<
              _$OticDatabase,
              $SessionSummariesTable,
              SessionSummary
            >,
          ),
          SessionSummary,
          PrefetchHooks Function()
        > {
  $$SessionSummariesTableTableManager(
    _$OticDatabase db,
    $SessionSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionSummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionSummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String> strengthsJson = const Value.absent(),
                Value<String> weaknessesJson = const Value.absent(),
                Value<String> highestStage = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<DateTime> sessionAt = const Value.absent(),
              }) => SessionSummariesCompanion(
                id: id,
                studentId: studentId,
                topic: topic,
                summary: summary,
                strengthsJson: strengthsJson,
                weaknessesJson: weaknessesJson,
                highestStage: highestStage,
                messageCount: messageCount,
                sessionAt: sessionAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String topic,
                required String summary,
                Value<String> strengthsJson = const Value.absent(),
                Value<String> weaknessesJson = const Value.absent(),
                Value<String> highestStage = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<DateTime> sessionAt = const Value.absent(),
              }) => SessionSummariesCompanion.insert(
                id: id,
                studentId: studentId,
                topic: topic,
                summary: summary,
                strengthsJson: strengthsJson,
                weaknessesJson: weaknessesJson,
                highestStage: highestStage,
                messageCount: messageCount,
                sessionAt: sessionAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $SessionSummariesTable,
      SessionSummary,
      $$SessionSummariesTableFilterComposer,
      $$SessionSummariesTableOrderingComposer,
      $$SessionSummariesTableAnnotationComposer,
      $$SessionSummariesTableCreateCompanionBuilder,
      $$SessionSummariesTableUpdateCompanionBuilder,
      (
        SessionSummary,
        BaseReferences<_$OticDatabase, $SessionSummariesTable, SessionSummary>,
      ),
      SessionSummary,
      PrefetchHooks Function()
    >;
typedef $$TopicProgressTableCreateCompanionBuilder =
    TopicProgressCompanion Function({
      Value<int> id,
      required int studentId,
      required String topic,
      Value<int> level,
      Value<int> sessionsCount,
      Value<DateTime> lastStudiedAt,
    });
typedef $$TopicProgressTableUpdateCompanionBuilder =
    TopicProgressCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> topic,
      Value<int> level,
      Value<int> sessionsCount,
      Value<DateTime> lastStudiedAt,
    });

class $$TopicProgressTableFilterComposer
    extends Composer<_$OticDatabase, $TopicProgressTable> {
  $$TopicProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionsCount => $composableBuilder(
    column: $table.sessionsCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastStudiedAt => $composableBuilder(
    column: $table.lastStudiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TopicProgressTableOrderingComposer
    extends Composer<_$OticDatabase, $TopicProgressTable> {
  $$TopicProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionsCount => $composableBuilder(
    column: $table.sessionsCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastStudiedAt => $composableBuilder(
    column: $table.lastStudiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TopicProgressTableAnnotationComposer
    extends Composer<_$OticDatabase, $TopicProgressTable> {
  $$TopicProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<int> get sessionsCount => $composableBuilder(
    column: $table.sessionsCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastStudiedAt => $composableBuilder(
    column: $table.lastStudiedAt,
    builder: (column) => column,
  );
}

class $$TopicProgressTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $TopicProgressTable,
          TopicProgressData,
          $$TopicProgressTableFilterComposer,
          $$TopicProgressTableOrderingComposer,
          $$TopicProgressTableAnnotationComposer,
          $$TopicProgressTableCreateCompanionBuilder,
          $$TopicProgressTableUpdateCompanionBuilder,
          (
            TopicProgressData,
            BaseReferences<
              _$OticDatabase,
              $TopicProgressTable,
              TopicProgressData
            >,
          ),
          TopicProgressData,
          PrefetchHooks Function()
        > {
  $$TopicProgressTableTableManager(_$OticDatabase db, $TopicProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TopicProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TopicProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TopicProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<int> sessionsCount = const Value.absent(),
                Value<DateTime> lastStudiedAt = const Value.absent(),
              }) => TopicProgressCompanion(
                id: id,
                studentId: studentId,
                topic: topic,
                level: level,
                sessionsCount: sessionsCount,
                lastStudiedAt: lastStudiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String topic,
                Value<int> level = const Value.absent(),
                Value<int> sessionsCount = const Value.absent(),
                Value<DateTime> lastStudiedAt = const Value.absent(),
              }) => TopicProgressCompanion.insert(
                id: id,
                studentId: studentId,
                topic: topic,
                level: level,
                sessionsCount: sessionsCount,
                lastStudiedAt: lastStudiedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TopicProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $TopicProgressTable,
      TopicProgressData,
      $$TopicProgressTableFilterComposer,
      $$TopicProgressTableOrderingComposer,
      $$TopicProgressTableAnnotationComposer,
      $$TopicProgressTableCreateCompanionBuilder,
      $$TopicProgressTableUpdateCompanionBuilder,
      (
        TopicProgressData,
        BaseReferences<_$OticDatabase, $TopicProgressTable, TopicProgressData>,
      ),
      TopicProgressData,
      PrefetchHooks Function()
    >;
typedef $$LearningPathsTableCreateCompanionBuilder =
    LearningPathsCompanion Function({
      Value<int> id,
      required int studentId,
      required String topic,
      required String title,
      required String description,
      Value<String> unitsJson,
      Value<int> totalLessons,
      Value<int> completedLessons,
      Value<int> currentUnit,
      Value<int> currentLesson,
      Value<DateTime> generatedAt,
      Value<DateTime> lastAccessedAt,
    });
typedef $$LearningPathsTableUpdateCompanionBuilder =
    LearningPathsCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> topic,
      Value<String> title,
      Value<String> description,
      Value<String> unitsJson,
      Value<int> totalLessons,
      Value<int> completedLessons,
      Value<int> currentUnit,
      Value<int> currentLesson,
      Value<DateTime> generatedAt,
      Value<DateTime> lastAccessedAt,
    });

class $$LearningPathsTableFilterComposer
    extends Composer<_$OticDatabase, $LearningPathsTable> {
  $$LearningPathsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitsJson => $composableBuilder(
    column: $table.unitsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalLessons => $composableBuilder(
    column: $table.totalLessons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedLessons => $composableBuilder(
    column: $table.completedLessons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentUnit => $composableBuilder(
    column: $table.currentUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentLesson => $composableBuilder(
    column: $table.currentLesson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LearningPathsTableOrderingComposer
    extends Composer<_$OticDatabase, $LearningPathsTable> {
  $$LearningPathsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitsJson => $composableBuilder(
    column: $table.unitsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalLessons => $composableBuilder(
    column: $table.totalLessons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedLessons => $composableBuilder(
    column: $table.completedLessons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentUnit => $composableBuilder(
    column: $table.currentUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentLesson => $composableBuilder(
    column: $table.currentLesson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LearningPathsTableAnnotationComposer
    extends Composer<_$OticDatabase, $LearningPathsTable> {
  $$LearningPathsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unitsJson =>
      $composableBuilder(column: $table.unitsJson, builder: (column) => column);

  GeneratedColumn<int> get totalLessons => $composableBuilder(
    column: $table.totalLessons,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedLessons => $composableBuilder(
    column: $table.completedLessons,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentUnit => $composableBuilder(
    column: $table.currentUnit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentLesson => $composableBuilder(
    column: $table.currentLesson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );
}

class $$LearningPathsTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $LearningPathsTable,
          LearningPath,
          $$LearningPathsTableFilterComposer,
          $$LearningPathsTableOrderingComposer,
          $$LearningPathsTableAnnotationComposer,
          $$LearningPathsTableCreateCompanionBuilder,
          $$LearningPathsTableUpdateCompanionBuilder,
          (
            LearningPath,
            BaseReferences<_$OticDatabase, $LearningPathsTable, LearningPath>,
          ),
          LearningPath,
          PrefetchHooks Function()
        > {
  $$LearningPathsTableTableManager(_$OticDatabase db, $LearningPathsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningPathsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningPathsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningPathsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> unitsJson = const Value.absent(),
                Value<int> totalLessons = const Value.absent(),
                Value<int> completedLessons = const Value.absent(),
                Value<int> currentUnit = const Value.absent(),
                Value<int> currentLesson = const Value.absent(),
                Value<DateTime> generatedAt = const Value.absent(),
                Value<DateTime> lastAccessedAt = const Value.absent(),
              }) => LearningPathsCompanion(
                id: id,
                studentId: studentId,
                topic: topic,
                title: title,
                description: description,
                unitsJson: unitsJson,
                totalLessons: totalLessons,
                completedLessons: completedLessons,
                currentUnit: currentUnit,
                currentLesson: currentLesson,
                generatedAt: generatedAt,
                lastAccessedAt: lastAccessedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String topic,
                required String title,
                required String description,
                Value<String> unitsJson = const Value.absent(),
                Value<int> totalLessons = const Value.absent(),
                Value<int> completedLessons = const Value.absent(),
                Value<int> currentUnit = const Value.absent(),
                Value<int> currentLesson = const Value.absent(),
                Value<DateTime> generatedAt = const Value.absent(),
                Value<DateTime> lastAccessedAt = const Value.absent(),
              }) => LearningPathsCompanion.insert(
                id: id,
                studentId: studentId,
                topic: topic,
                title: title,
                description: description,
                unitsJson: unitsJson,
                totalLessons: totalLessons,
                completedLessons: completedLessons,
                currentUnit: currentUnit,
                currentLesson: currentLesson,
                generatedAt: generatedAt,
                lastAccessedAt: lastAccessedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LearningPathsTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $LearningPathsTable,
      LearningPath,
      $$LearningPathsTableFilterComposer,
      $$LearningPathsTableOrderingComposer,
      $$LearningPathsTableAnnotationComposer,
      $$LearningPathsTableCreateCompanionBuilder,
      $$LearningPathsTableUpdateCompanionBuilder,
      (
        LearningPath,
        BaseReferences<_$OticDatabase, $LearningPathsTable, LearningPath>,
      ),
      LearningPath,
      PrefetchHooks Function()
    >;
typedef $$EarnedBadgesTableCreateCompanionBuilder =
    EarnedBadgesCompanion Function({
      Value<int> id,
      required int studentId,
      required String badgeId,
      required String badgeName,
      Value<DateTime> earnedAt,
    });
typedef $$EarnedBadgesTableUpdateCompanionBuilder =
    EarnedBadgesCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> badgeId,
      Value<String> badgeName,
      Value<DateTime> earnedAt,
    });

class $$EarnedBadgesTableFilterComposer
    extends Composer<_$OticDatabase, $EarnedBadgesTable> {
  $$EarnedBadgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get badgeName => $composableBuilder(
    column: $table.badgeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get earnedAt => $composableBuilder(
    column: $table.earnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EarnedBadgesTableOrderingComposer
    extends Composer<_$OticDatabase, $EarnedBadgesTable> {
  $$EarnedBadgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get badgeName => $composableBuilder(
    column: $table.badgeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get earnedAt => $composableBuilder(
    column: $table.earnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EarnedBadgesTableAnnotationComposer
    extends Composer<_$OticDatabase, $EarnedBadgesTable> {
  $$EarnedBadgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get badgeId =>
      $composableBuilder(column: $table.badgeId, builder: (column) => column);

  GeneratedColumn<String> get badgeName =>
      $composableBuilder(column: $table.badgeName, builder: (column) => column);

  GeneratedColumn<DateTime> get earnedAt =>
      $composableBuilder(column: $table.earnedAt, builder: (column) => column);
}

class $$EarnedBadgesTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $EarnedBadgesTable,
          EarnedBadge,
          $$EarnedBadgesTableFilterComposer,
          $$EarnedBadgesTableOrderingComposer,
          $$EarnedBadgesTableAnnotationComposer,
          $$EarnedBadgesTableCreateCompanionBuilder,
          $$EarnedBadgesTableUpdateCompanionBuilder,
          (
            EarnedBadge,
            BaseReferences<_$OticDatabase, $EarnedBadgesTable, EarnedBadge>,
          ),
          EarnedBadge,
          PrefetchHooks Function()
        > {
  $$EarnedBadgesTableTableManager(_$OticDatabase db, $EarnedBadgesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EarnedBadgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EarnedBadgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EarnedBadgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> badgeId = const Value.absent(),
                Value<String> badgeName = const Value.absent(),
                Value<DateTime> earnedAt = const Value.absent(),
              }) => EarnedBadgesCompanion(
                id: id,
                studentId: studentId,
                badgeId: badgeId,
                badgeName: badgeName,
                earnedAt: earnedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String badgeId,
                required String badgeName,
                Value<DateTime> earnedAt = const Value.absent(),
              }) => EarnedBadgesCompanion.insert(
                id: id,
                studentId: studentId,
                badgeId: badgeId,
                badgeName: badgeName,
                earnedAt: earnedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EarnedBadgesTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $EarnedBadgesTable,
      EarnedBadge,
      $$EarnedBadgesTableFilterComposer,
      $$EarnedBadgesTableOrderingComposer,
      $$EarnedBadgesTableAnnotationComposer,
      $$EarnedBadgesTableCreateCompanionBuilder,
      $$EarnedBadgesTableUpdateCompanionBuilder,
      (
        EarnedBadge,
        BaseReferences<_$OticDatabase, $EarnedBadgesTable, EarnedBadge>,
      ),
      EarnedBadge,
      PrefetchHooks Function()
    >;
typedef $$StudentProjectsTableCreateCompanionBuilder =
    StudentProjectsCompanion Function({
      Value<int> id,
      required int studentId,
      required String title,
      required String topic,
      required String projectType,
      Value<String> stepsJson,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$StudentProjectsTableUpdateCompanionBuilder =
    StudentProjectsCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> title,
      Value<String> topic,
      Value<String> projectType,
      Value<String> stepsJson,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$StudentProjectsTableFilterComposer
    extends Composer<_$OticDatabase, $StudentProjectsTable> {
  $$StudentProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stepsJson => $composableBuilder(
    column: $table.stepsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StudentProjectsTableOrderingComposer
    extends Composer<_$OticDatabase, $StudentProjectsTable> {
  $$StudentProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stepsJson => $composableBuilder(
    column: $table.stepsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StudentProjectsTableAnnotationComposer
    extends Composer<_$OticDatabase, $StudentProjectsTable> {
  $$StudentProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get projectType => $composableBuilder(
    column: $table.projectType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stepsJson =>
      $composableBuilder(column: $table.stepsJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StudentProjectsTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $StudentProjectsTable,
          StudentProject,
          $$StudentProjectsTableFilterComposer,
          $$StudentProjectsTableOrderingComposer,
          $$StudentProjectsTableAnnotationComposer,
          $$StudentProjectsTableCreateCompanionBuilder,
          $$StudentProjectsTableUpdateCompanionBuilder,
          (
            StudentProject,
            BaseReferences<
              _$OticDatabase,
              $StudentProjectsTable,
              StudentProject
            >,
          ),
          StudentProject,
          PrefetchHooks Function()
        > {
  $$StudentProjectsTableTableManager(
    _$OticDatabase db,
    $StudentProjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudentProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StudentProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudentProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> projectType = const Value.absent(),
                Value<String> stepsJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StudentProjectsCompanion(
                id: id,
                studentId: studentId,
                title: title,
                topic: topic,
                projectType: projectType,
                stepsJson: stepsJson,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String title,
                required String topic,
                required String projectType,
                Value<String> stepsJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StudentProjectsCompanion.insert(
                id: id,
                studentId: studentId,
                title: title,
                topic: topic,
                projectType: projectType,
                stepsJson: stepsJson,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StudentProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $StudentProjectsTable,
      StudentProject,
      $$StudentProjectsTableFilterComposer,
      $$StudentProjectsTableOrderingComposer,
      $$StudentProjectsTableAnnotationComposer,
      $$StudentProjectsTableCreateCompanionBuilder,
      $$StudentProjectsTableUpdateCompanionBuilder,
      (
        StudentProject,
        BaseReferences<_$OticDatabase, $StudentProjectsTable, StudentProject>,
      ),
      StudentProject,
      PrefetchHooks Function()
    >;
typedef $$WebsiteProjectsTableCreateCompanionBuilder =
    WebsiteProjectsCompanion Function({
      Value<int> id,
      required int studentId,
      required String title,
      Value<String> themeColor,
      Value<String> blocksJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$WebsiteProjectsTableUpdateCompanionBuilder =
    WebsiteProjectsCompanion Function({
      Value<int> id,
      Value<int> studentId,
      Value<String> title,
      Value<String> themeColor,
      Value<String> blocksJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$WebsiteProjectsTableFilterComposer
    extends Composer<_$OticDatabase, $WebsiteProjectsTable> {
  $$WebsiteProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blocksJson => $composableBuilder(
    column: $table.blocksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WebsiteProjectsTableOrderingComposer
    extends Composer<_$OticDatabase, $WebsiteProjectsTable> {
  $$WebsiteProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get studentId => $composableBuilder(
    column: $table.studentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blocksJson => $composableBuilder(
    column: $table.blocksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WebsiteProjectsTableAnnotationComposer
    extends Composer<_$OticDatabase, $WebsiteProjectsTable> {
  $$WebsiteProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blocksJson => $composableBuilder(
    column: $table.blocksJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WebsiteProjectsTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $WebsiteProjectsTable,
          WebsiteProject,
          $$WebsiteProjectsTableFilterComposer,
          $$WebsiteProjectsTableOrderingComposer,
          $$WebsiteProjectsTableAnnotationComposer,
          $$WebsiteProjectsTableCreateCompanionBuilder,
          $$WebsiteProjectsTableUpdateCompanionBuilder,
          (
            WebsiteProject,
            BaseReferences<
              _$OticDatabase,
              $WebsiteProjectsTable,
              WebsiteProject
            >,
          ),
          WebsiteProject,
          PrefetchHooks Function()
        > {
  $$WebsiteProjectsTableTableManager(
    _$OticDatabase db,
    $WebsiteProjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WebsiteProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WebsiteProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WebsiteProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> themeColor = const Value.absent(),
                Value<String> blocksJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WebsiteProjectsCompanion(
                id: id,
                studentId: studentId,
                title: title,
                themeColor: themeColor,
                blocksJson: blocksJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studentId,
                required String title,
                Value<String> themeColor = const Value.absent(),
                Value<String> blocksJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WebsiteProjectsCompanion.insert(
                id: id,
                studentId: studentId,
                title: title,
                themeColor: themeColor,
                blocksJson: blocksJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WebsiteProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $WebsiteProjectsTable,
      WebsiteProject,
      $$WebsiteProjectsTableFilterComposer,
      $$WebsiteProjectsTableOrderingComposer,
      $$WebsiteProjectsTableAnnotationComposer,
      $$WebsiteProjectsTableCreateCompanionBuilder,
      $$WebsiteProjectsTableUpdateCompanionBuilder,
      (
        WebsiteProject,
        BaseReferences<_$OticDatabase, $WebsiteProjectsTable, WebsiteProject>,
      ),
      WebsiteProject,
      PrefetchHooks Function()
    >;
typedef $$TranslationCacheEntriesTableCreateCompanionBuilder =
    TranslationCacheEntriesCompanion Function({
      Value<int> id,
      required String cacheKey,
      required String langCode,
      required String direction,
      required String modelTag,
      required String sourceText,
      required String translatedText,
      Value<int> useCount,
      Value<DateTime> lastUsedAt,
      Value<DateTime> createdAt,
    });
typedef $$TranslationCacheEntriesTableUpdateCompanionBuilder =
    TranslationCacheEntriesCompanion Function({
      Value<int> id,
      Value<String> cacheKey,
      Value<String> langCode,
      Value<String> direction,
      Value<String> modelTag,
      Value<String> sourceText,
      Value<String> translatedText,
      Value<int> useCount,
      Value<DateTime> lastUsedAt,
      Value<DateTime> createdAt,
    });

class $$TranslationCacheEntriesTableFilterComposer
    extends Composer<_$OticDatabase, $TranslationCacheEntriesTable> {
  $$TranslationCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get langCode => $composableBuilder(
    column: $table.langCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelTag => $composableBuilder(
    column: $table.modelTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get translatedText => $composableBuilder(
    column: $table.translatedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TranslationCacheEntriesTableOrderingComposer
    extends Composer<_$OticDatabase, $TranslationCacheEntriesTable> {
  $$TranslationCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get langCode => $composableBuilder(
    column: $table.langCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelTag => $composableBuilder(
    column: $table.modelTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get translatedText => $composableBuilder(
    column: $table.translatedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TranslationCacheEntriesTableAnnotationComposer
    extends Composer<_$OticDatabase, $TranslationCacheEntriesTable> {
  $$TranslationCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get langCode =>
      $composableBuilder(column: $table.langCode, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get modelTag =>
      $composableBuilder(column: $table.modelTag, builder: (column) => column);

  GeneratedColumn<String> get sourceText => $composableBuilder(
    column: $table.sourceText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get translatedText => $composableBuilder(
    column: $table.translatedText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TranslationCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $TranslationCacheEntriesTable,
          TranslationCacheEntry,
          $$TranslationCacheEntriesTableFilterComposer,
          $$TranslationCacheEntriesTableOrderingComposer,
          $$TranslationCacheEntriesTableAnnotationComposer,
          $$TranslationCacheEntriesTableCreateCompanionBuilder,
          $$TranslationCacheEntriesTableUpdateCompanionBuilder,
          (
            TranslationCacheEntry,
            BaseReferences<
              _$OticDatabase,
              $TranslationCacheEntriesTable,
              TranslationCacheEntry
            >,
          ),
          TranslationCacheEntry,
          PrefetchHooks Function()
        > {
  $$TranslationCacheEntriesTableTableManager(
    _$OticDatabase db,
    $TranslationCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TranslationCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TranslationCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TranslationCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> langCode = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> modelTag = const Value.absent(),
                Value<String> sourceText = const Value.absent(),
                Value<String> translatedText = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TranslationCacheEntriesCompanion(
                id: id,
                cacheKey: cacheKey,
                langCode: langCode,
                direction: direction,
                modelTag: modelTag,
                sourceText: sourceText,
                translatedText: translatedText,
                useCount: useCount,
                lastUsedAt: lastUsedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cacheKey,
                required String langCode,
                required String direction,
                required String modelTag,
                required String sourceText,
                required String translatedText,
                Value<int> useCount = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TranslationCacheEntriesCompanion.insert(
                id: id,
                cacheKey: cacheKey,
                langCode: langCode,
                direction: direction,
                modelTag: modelTag,
                sourceText: sourceText,
                translatedText: translatedText,
                useCount: useCount,
                lastUsedAt: lastUsedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TranslationCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $TranslationCacheEntriesTable,
      TranslationCacheEntry,
      $$TranslationCacheEntriesTableFilterComposer,
      $$TranslationCacheEntriesTableOrderingComposer,
      $$TranslationCacheEntriesTableAnnotationComposer,
      $$TranslationCacheEntriesTableCreateCompanionBuilder,
      $$TranslationCacheEntriesTableUpdateCompanionBuilder,
      (
        TranslationCacheEntry,
        BaseReferences<
          _$OticDatabase,
          $TranslationCacheEntriesTable,
          TranslationCacheEntry
        >,
      ),
      TranslationCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$TopicResourcesTableCreateCompanionBuilder =
    TopicResourcesCompanion Function({
      Value<int> id,
      required String subjectId,
      required String topicKey,
      Value<int> termMarker,
      required String resourceTitle,
      required String contentChunk,
      required String createdAt,
    });
typedef $$TopicResourcesTableUpdateCompanionBuilder =
    TopicResourcesCompanion Function({
      Value<int> id,
      Value<String> subjectId,
      Value<String> topicKey,
      Value<int> termMarker,
      Value<String> resourceTitle,
      Value<String> contentChunk,
      Value<String> createdAt,
    });

class $$TopicResourcesTableFilterComposer
    extends Composer<_$OticDatabase, $TopicResourcesTable> {
  $$TopicResourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicKey => $composableBuilder(
    column: $table.topicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get termMarker => $composableBuilder(
    column: $table.termMarker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceTitle => $composableBuilder(
    column: $table.resourceTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentChunk => $composableBuilder(
    column: $table.contentChunk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TopicResourcesTableOrderingComposer
    extends Composer<_$OticDatabase, $TopicResourcesTable> {
  $$TopicResourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicKey => $composableBuilder(
    column: $table.topicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get termMarker => $composableBuilder(
    column: $table.termMarker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceTitle => $composableBuilder(
    column: $table.resourceTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentChunk => $composableBuilder(
    column: $table.contentChunk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TopicResourcesTableAnnotationComposer
    extends Composer<_$OticDatabase, $TopicResourcesTable> {
  $$TopicResourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get topicKey =>
      $composableBuilder(column: $table.topicKey, builder: (column) => column);

  GeneratedColumn<int> get termMarker => $composableBuilder(
    column: $table.termMarker,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resourceTitle => $composableBuilder(
    column: $table.resourceTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentChunk => $composableBuilder(
    column: $table.contentChunk,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TopicResourcesTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $TopicResourcesTable,
          TopicResource,
          $$TopicResourcesTableFilterComposer,
          $$TopicResourcesTableOrderingComposer,
          $$TopicResourcesTableAnnotationComposer,
          $$TopicResourcesTableCreateCompanionBuilder,
          $$TopicResourcesTableUpdateCompanionBuilder,
          (
            TopicResource,
            BaseReferences<_$OticDatabase, $TopicResourcesTable, TopicResource>,
          ),
          TopicResource,
          PrefetchHooks Function()
        > {
  $$TopicResourcesTableTableManager(
    _$OticDatabase db,
    $TopicResourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TopicResourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TopicResourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TopicResourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> topicKey = const Value.absent(),
                Value<int> termMarker = const Value.absent(),
                Value<String> resourceTitle = const Value.absent(),
                Value<String> contentChunk = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => TopicResourcesCompanion(
                id: id,
                subjectId: subjectId,
                topicKey: topicKey,
                termMarker: termMarker,
                resourceTitle: resourceTitle,
                contentChunk: contentChunk,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subjectId,
                required String topicKey,
                Value<int> termMarker = const Value.absent(),
                required String resourceTitle,
                required String contentChunk,
                required String createdAt,
              }) => TopicResourcesCompanion.insert(
                id: id,
                subjectId: subjectId,
                topicKey: topicKey,
                termMarker: termMarker,
                resourceTitle: resourceTitle,
                contentChunk: contentChunk,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TopicResourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $TopicResourcesTable,
      TopicResource,
      $$TopicResourcesTableFilterComposer,
      $$TopicResourcesTableOrderingComposer,
      $$TopicResourcesTableAnnotationComposer,
      $$TopicResourcesTableCreateCompanionBuilder,
      $$TopicResourcesTableUpdateCompanionBuilder,
      (
        TopicResource,
        BaseReferences<_$OticDatabase, $TopicResourcesTable, TopicResource>,
      ),
      TopicResource,
      PrefetchHooks Function()
    >;
typedef $$CustomSubjectsTableCreateCompanionBuilder =
    CustomSubjectsCompanion Function({
      Value<int> id,
      required String subjectId,
      required String name,
      Value<String> icon,
      Value<String> color,
      required String createdAt,
    });
typedef $$CustomSubjectsTableUpdateCompanionBuilder =
    CustomSubjectsCompanion Function({
      Value<int> id,
      Value<String> subjectId,
      Value<String> name,
      Value<String> icon,
      Value<String> color,
      Value<String> createdAt,
    });

class $$CustomSubjectsTableFilterComposer
    extends Composer<_$OticDatabase, $CustomSubjectsTable> {
  $$CustomSubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomSubjectsTableOrderingComposer
    extends Composer<_$OticDatabase, $CustomSubjectsTable> {
  $$CustomSubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomSubjectsTableAnnotationComposer
    extends Composer<_$OticDatabase, $CustomSubjectsTable> {
  $$CustomSubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CustomSubjectsTableTableManager
    extends
        RootTableManager<
          _$OticDatabase,
          $CustomSubjectsTable,
          CustomSubject,
          $$CustomSubjectsTableFilterComposer,
          $$CustomSubjectsTableOrderingComposer,
          $$CustomSubjectsTableAnnotationComposer,
          $$CustomSubjectsTableCreateCompanionBuilder,
          $$CustomSubjectsTableUpdateCompanionBuilder,
          (
            CustomSubject,
            BaseReferences<_$OticDatabase, $CustomSubjectsTable, CustomSubject>,
          ),
          CustomSubject,
          PrefetchHooks Function()
        > {
  $$CustomSubjectsTableTableManager(
    _$OticDatabase db,
    $CustomSubjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomSubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomSubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomSubjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => CustomSubjectsCompanion(
                id: id,
                subjectId: subjectId,
                name: name,
                icon: icon,
                color: color,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String subjectId,
                required String name,
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                required String createdAt,
              }) => CustomSubjectsCompanion.insert(
                id: id,
                subjectId: subjectId,
                name: name,
                icon: icon,
                color: color,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomSubjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$OticDatabase,
      $CustomSubjectsTable,
      CustomSubject,
      $$CustomSubjectsTableFilterComposer,
      $$CustomSubjectsTableOrderingComposer,
      $$CustomSubjectsTableAnnotationComposer,
      $$CustomSubjectsTableCreateCompanionBuilder,
      $$CustomSubjectsTableUpdateCompanionBuilder,
      (
        CustomSubject,
        BaseReferences<_$OticDatabase, $CustomSubjectsTable, CustomSubject>,
      ),
      CustomSubject,
      PrefetchHooks Function()
    >;

class $OticDatabaseManager {
  final _$OticDatabase _db;
  $OticDatabaseManager(this._db);
  $$StudentsTableTableManager get students =>
      $$StudentsTableTableManager(_db, _db.students);
  $$SessionSummariesTableTableManager get sessionSummaries =>
      $$SessionSummariesTableTableManager(_db, _db.sessionSummaries);
  $$TopicProgressTableTableManager get topicProgress =>
      $$TopicProgressTableTableManager(_db, _db.topicProgress);
  $$LearningPathsTableTableManager get learningPaths =>
      $$LearningPathsTableTableManager(_db, _db.learningPaths);
  $$EarnedBadgesTableTableManager get earnedBadges =>
      $$EarnedBadgesTableTableManager(_db, _db.earnedBadges);
  $$StudentProjectsTableTableManager get studentProjects =>
      $$StudentProjectsTableTableManager(_db, _db.studentProjects);
  $$WebsiteProjectsTableTableManager get websiteProjects =>
      $$WebsiteProjectsTableTableManager(_db, _db.websiteProjects);
  $$TranslationCacheEntriesTableTableManager get translationCacheEntries =>
      $$TranslationCacheEntriesTableTableManager(
        _db,
        _db.translationCacheEntries,
      );
  $$TopicResourcesTableTableManager get topicResources =>
      $$TopicResourcesTableTableManager(_db, _db.topicResources);
  $$CustomSubjectsTableTableManager get customSubjects =>
      $$CustomSubjectsTableTableManager(_db, _db.customSubjects);
}
