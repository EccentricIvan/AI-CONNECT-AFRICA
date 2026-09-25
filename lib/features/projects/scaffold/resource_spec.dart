/// Data model a generated project's backend exposes.
///
/// A small, closed set of column types keeps every generated Python file
/// inside a shape the scaffold tests actually exercise — the 1.5B coder never
/// invents a schema, so a build cannot produce a backend that fails to start.
enum FieldType { string, text, integer, decimal, boolean }

class FieldSpec {
  const FieldSpec(
    this.name,
    this.type, {
    this.label,
    this.required = false,
    this.sample,
  });

  /// snake_case column / JSON key.
  final String name;
  final FieldType type;
  final String? label;

  /// Required on create (validated by Pydantic and by the frontend form).
  final bool required;

  /// Example value used by the generated tests and the README curl example.
  final Object? sample;

  String get displayLabel {
    final l = label;
    if (l != null) return l;
    final words = name.split('_');
    return [
      for (final w in words)
        if (w.isNotEmpty) '${w[0].toUpperCase()}${w.substring(1)}',
    ].join(' ');
  }

  Object get sampleValue {
    final s = sample;
    if (s != null) return s;
    return switch (type) {
      FieldType.string => 'Sample $name',
      FieldType.text => 'Some longer $name text.',
      FieldType.integer => 3,
      FieldType.decimal => 12.5,
      FieldType.boolean => false,
    };
  }
}

class ResourceSpec {
  const ResourceSpec({
    required this.className,
    required this.route,
    required this.label,
    required this.fields,
  });

  /// PascalCase singular, e.g. `Task`.
  final String className;

  /// URL segment and table name, plural snake_case, e.g. `tasks`.
  final String route;

  /// Heading shown above the data panel, e.g. `Tasks`.
  final String label;

  final List<FieldSpec> fields;

  /// Python identifier for one row (`task`), used in route function names.
  String get singular {
    final buf = StringBuffer();
    for (var i = 0; i < className.length; i++) {
      final c = className[i];
      final upper = c.toUpperCase() == c && c.toLowerCase() != c;
      if (upper && i > 0) buf.write('_');
      buf.write(c.toLowerCase());
    }
    return buf.toString();
  }

  Map<String, Object> get samplePayload => {
        for (final f in fields) f.name: f.sampleValue,
      };
}

const _task = ResourceSpec(
  className: 'Task',
  route: 'tasks',
  label: 'Tasks',
  fields: [
    FieldSpec('title', FieldType.string, required: true, sample: 'Finish homework'),
    FieldSpec('priority', FieldType.string, sample: 'high'),
    FieldSpec('due', FieldType.string, label: 'Due date', sample: '2026-10-01'),
    FieldSpec('done', FieldType.boolean),
  ],
);

const _note = ResourceSpec(
  className: 'Note',
  route: 'notes',
  label: 'Notes',
  fields: [
    FieldSpec('title', FieldType.string, required: true, sample: 'Biology revision'),
    FieldSpec('body', FieldType.text, sample: 'Cells are the basic unit of life.'),
    FieldSpec('favorite', FieldType.boolean),
  ],
);

const _expense = ResourceSpec(
  className: 'Expense',
  route: 'expenses',
  label: 'Expenses',
  fields: [
    FieldSpec('title', FieldType.string, required: true, sample: 'Bus fare'),
    FieldSpec('amount', FieldType.decimal, required: true, sample: 2500.0),
    FieldSpec('category', FieldType.string, sample: 'Transport'),
    FieldSpec('spent_on', FieldType.string, label: 'Date', sample: '2026-09-25'),
  ],
);

const _question = ResourceSpec(
  className: 'Question',
  route: 'questions',
  label: 'Questions',
  fields: [
    FieldSpec('prompt', FieldType.string, required: true, sample: 'What is 7 x 8?'),
    FieldSpec('options', FieldType.text,
        label: 'Options (one per line)', sample: '54\n56\n58'),
    FieldSpec('answer', FieldType.string, required: true, sample: '56'),
  ],
);

const _score = ResourceSpec(
  className: 'Score',
  route: 'scores',
  label: 'Scores',
  fields: [
    FieldSpec('player', FieldType.string, required: true, sample: 'Amina'),
    FieldSpec('points', FieldType.integer, required: true, sample: 8),
  ],
);

const _habit = ResourceSpec(
  className: 'Habit',
  route: 'habits',
  label: 'Habits',
  fields: [
    FieldSpec('name', FieldType.string, required: true, sample: 'Read 20 minutes'),
    FieldSpec('streak', FieldType.integer, sample: 4),
    FieldSpec('done_today', FieldType.boolean, label: 'Done today'),
  ],
);

const _product = ResourceSpec(
  className: 'Product',
  route: 'products',
  label: 'Products',
  fields: [
    FieldSpec('name', FieldType.string, required: true, sample: 'Fresh tomatoes'),
    FieldSpec('price', FieldType.decimal, required: true, sample: 3000.0),
    FieldSpec('stock', FieldType.integer, sample: 20),
    FieldSpec('seller', FieldType.string, sample: 'Mama Grace'),
    FieldSpec('favorite', FieldType.boolean),
  ],
);

const _field = ResourceSpec(
  className: 'Field',
  route: 'fields',
  label: 'Fields',
  fields: [
    FieldSpec('name', FieldType.string, required: true, sample: 'North field'),
    FieldSpec('crop', FieldType.string, sample: 'Maize'),
    FieldSpec('area', FieldType.string, sample: '2 ha'),
    FieldSpec('note', FieldType.text, sample: 'Healthy growth.'),
  ],
);

const _harvest = ResourceSpec(
  className: 'Harvest',
  route: 'harvests',
  label: 'Harvest log',
  fields: [
    FieldSpec('crop', FieldType.string, required: true, sample: 'Maize'),
    FieldSpec('amount_kg', FieldType.decimal, label: 'Amount (kg)', sample: 450.0),
    FieldSpec('harvested_on', FieldType.string, label: 'Date', sample: '2026-09-20'),
  ],
);

const _course = ResourceSpec(
  className: 'Course',
  route: 'courses',
  label: 'Courses',
  fields: [
    FieldSpec('title', FieldType.string, required: true, sample: 'Intro to Python'),
    FieldSpec('description', FieldType.text, sample: 'Variables, loops and functions.'),
    FieldSpec('mentor', FieldType.string, sample: 'Mr. Okello'),
    FieldSpec('lessons', FieldType.integer, sample: 12),
    FieldSpec('progress', FieldType.integer, label: 'Progress (%)', sample: 25),
  ],
);

const _sale = ResourceSpec(
  className: 'Sale',
  route: 'sales',
  label: 'Sales',
  fields: [
    FieldSpec('item', FieldType.string, required: true, sample: 'Sugar 1kg'),
    FieldSpec('quantity', FieldType.integer, required: true, sample: 2),
    FieldSpec('amount', FieldType.decimal, required: true, sample: 9000.0),
  ],
);

const _post = ResourceSpec(
  className: 'Post',
  route: 'posts',
  label: 'Posts',
  fields: [
    FieldSpec('author', FieldType.string, required: true, sample: 'Brian'),
    FieldSpec('body', FieldType.text, required: true, sample: 'Football practice at 4pm!'),
    FieldSpec('group_name', FieldType.string, label: 'Group', sample: 'Sports club'),
    FieldSpec('likes', FieldType.integer, sample: 0),
  ],
);

const _order = ResourceSpec(
  className: 'Order',
  route: 'orders',
  label: 'Orders',
  fields: [
    FieldSpec('client', FieldType.string, required: true, sample: 'Kato Traders'),
    FieldSpec('stage', FieldType.string, sample: 'new'),
    FieldSpec('amount', FieldType.decimal, sample: 150000.0),
    FieldSpec('notes', FieldType.text, sample: 'Deliver on Friday.'),
  ],
);

const _calculation = ResourceSpec(
  className: 'Calculation',
  route: 'calculations',
  label: 'Saved calculations',
  fields: [
    FieldSpec('expression', FieldType.string, required: true, sample: '12 * 4'),
    FieldSpec('result', FieldType.string, required: true, sample: '48'),
  ],
);

const _item = ResourceSpec(
  className: 'Item',
  route: 'items',
  label: 'Items',
  fields: [
    FieldSpec('title', FieldType.string, required: true, sample: 'First item'),
    FieldSpec('description', FieldType.text, sample: 'Describe it here.'),
    FieldSpec('done', FieldType.boolean),
  ],
);

/// Contact form messages every generated website stores.
const kContactMessageResource = ResourceSpec(
  className: 'ContactMessage',
  route: 'contact',
  label: 'Messages',
  fields: [
    FieldSpec('name', FieldType.string, required: true, sample: 'Sarah'),
    FieldSpec('email', FieldType.string, sample: 'sarah@example.com'),
    FieldSpec('phone', FieldType.string, sample: '+256 700 000000'),
    FieldSpec('message', FieldType.text, required: true, sample: 'Do you deliver?'),
  ],
);

/// App type id (App chat builder and App Dev Lab ids) → backend resources.
///
/// Unknown ids fall back to a generic `Item` list, so a new app type added
/// to a builder still gets a working backend before it gets its own entry.
List<ResourceSpec> resourcesForAppType(String appTypeId) {
  return switch (appTypeId) {
    'todo' => const [_task],
    'notes' => const [_note],
    'budget' || 'expense' => const [_expense],
    'quiz' => const [_question, _score],
    'habits' => const [_habit],
    'market' || 'shop' || 'products' => const [_product],
    'farm' => const [_field, _harvest],
    'learn' || 'eduplatform' => const [_course],
    'pos' => const [_sale, _product],
    'social' => const [_post],
    'orders' => const [_order],
    'calculator' => const [_calculation],
    _ => const [_item],
  };
}
