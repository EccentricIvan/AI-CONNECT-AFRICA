import 'dart:math';

/// Catalog entry for the App chat builder's "pick from a list" fallback.
///
/// Moved out of `app_chat_builder_screen.dart` (was private `_AppType`) so
/// [classifyAppType] and the list picker can both read it.
class AppTypeEntry {
  const AppTypeEntry(
    this.id,
    this.name,
    this.featureOptions, {
    this.templateId = 'generic',
    this.autoFields = const {},
    this.keywords = const [],
  });

  final String id;
  final String name;
  final List<String> featureOptions;

  /// Screen template under `assets/templates/apps/` this type builds from.
  final String templateId;

  /// Sample copy pools filled in at build time, so a student's screen looks
  /// like a real product instead of empty placeholders.
  final Map<String, List<String>> autoFields;

  /// Phrases that indicate a free-text description matches this type. Used
  /// by [classifyAppType], longest match wins.
  final List<String> keywords;
}

final _rng = Random();
String pickAutoField(List<String> options) =>
    options[_rng.nextInt(options.length)];

/// Always-available fallback when no free-text description matches a known
/// type well — never leaves the app type unresolved.
const kGenericAppType = AppTypeEntry('custom', 'Custom App', ['Home screen']);

const kAppTypes = <AppTypeEntry>[
  AppTypeEntry(
    'notes',
    'School Notes',
    ['Note list', 'Add note form', 'Search notes', 'Favorite notes'],
    keywords: ['note', 'school notes'],
  ),
  AppTypeEntry(
    'budget',
    'Budget Tracker',
    ['Expense list', 'Add expense', 'Category totals', 'Savings goal'],
    keywords: ['budget', 'money', 'expense'],
  ),
  AppTypeEntry(
    'quiz',
    'Quiz Game',
    ['Question screen', 'Score tracker', 'Multiple choice', 'Restart quiz'],
    keywords: ['quiz', 'game'],
  ),
  AppTypeEntry(
    'habits',
    'Habit Tracker',
    ['Daily checklist', 'Streak counter', 'Add habit', 'Weekly progress'],
    keywords: ['habit'],
  ),
  AppTypeEntry(
    'todo',
    'To-Do List',
    ['Task list', 'Add task', 'Mark done', 'Priority tags'],
    keywords: ['todo', 'to-do', 'task'],
  ),
  AppTypeEntry(
    'market',
    'Local Market',
    ['Product cards', 'Seller contact', 'Search items', 'Favorites'],
    keywords: ['market', 'sell'],
  ),
  AppTypeEntry(
    'farm',
    'Farm / Crop Monitor',
    ['Field list', 'Weather today', 'Crop health', 'Harvest log'],
    templateId: 'farm',
    keywords: ['farm', 'crop', 'agri', 'harvest', 'garden'],
    autoFields: {
      'owner_name': ['Annca', 'Harris', 'Joseph', 'Amina'],
      'location': [
        'Mukono, Uganda',
        'Central Valley',
        'Jinja, Uganda',
        'Nakuru, Kenya',
      ],
      'temperature': ['24°C', '32°C', '27°C'],
      'humidity': ['85%', '78%', '64%'],
      'rainfall': ['8 mm', '0 mm', '12 mm'],
      'wind': ['13 km/h', '7 m/s', '9 km/h'],
      'crop1': ['Maize', 'Rice', 'Carrots'],
      'crop2': ['Beans', 'Wheat', 'Vegetable'],
      'crop3': ['Coffee', 'Potato', 'Fruit'],
      'field1_name': ['My Garden Field', 'North Field', 'Riverside Plot'],
      'field1_note': [
        'Healthy growth, irrigation on schedule.',
        'Ready for harvest in two weeks.',
      ],
      'field2_name': ['East Field', 'Hill Plot', 'Lower Field'],
      'field2_note': [
        'Watch for pests this week.',
        'Newly planted, germinating well.',
      ],
      'total_area': ['12 ha', '45 acres', '8 ha'],
      'plant_age': ['45 days', '2 months', '18 days'],
      'soil_quality': ['75%', '82%', '68%'],
      'yield_amount': ['15 tons', '22 tons', '9 tons'],
    },
  ),
  AppTypeEntry(
    'shop',
    'Online Shop / Store',
    ['Product grid', 'Search items', 'Cart & checkout', 'Favorites'],
    templateId: 'shop',
    keywords: ['online shop', 'store', 'ecommerce', 'e-commerce', 'shop'],
    autoFields: {
      'location': [
        'Kampala Road, 21',
        'Main Street, Nairobi',
        'Plot 8, Entebbe',
      ],
      'cat1': ['Home', 'Furniture', 'Fabrics'],
      'cat2': ['Clothes', 'Fashion', 'Shoes'],
      'cat3': ['Electronics', 'Lighting', 'Phones'],
      'cat4': ['Plants', 'Decor', 'Garden'],
      'promo_title': [
        'Pay in instalments',
        'Free delivery this week',
        'Save up to 30%',
      ],
      'promo_note': [
        'No deposit needed on selected items.',
        'On every order above 50,000 UGX.',
      ],
      'product1_name': ['Swivel chair', 'Woven basket', 'Cushion cover'],
      'product1_price': ['120,000 UGX', '35,000 UGX', '18,000 UGX'],
      'product2_name': ['Table lamp', 'Glass tumbler', 'Wall clock'],
      'product2_price': ['45,000 UGX', '9,000 UGX', '60,000 UGX'],
    },
  ),
  AppTypeEntry(
    'learn',
    'Learning / Course App',
    ['Course list', 'Lesson player', 'Progress tracker', 'Quizzes'],
    templateId: 'learn',
    keywords: ['learn', 'course', 'lesson', 'study', 'education'],
    autoFields: {
      'learner_name': ['Sofia', 'Jerel', 'Amina', 'Daniel'],
      'banner_title': [
        'Find your lesson for today',
        'Learn something new today',
        'Pick up where you left off',
      ],
      'banner_note': [
        'Over 100 offline lessons across every subject on your device.',
        'Short lessons that work with no internet at all.',
      ],
      'cat1': ['Design', 'Art', 'Writing'],
      'cat2': ['Coding', 'Web Design', 'ICT'],
      'cat3': ['Maths', 'Numbers', 'Algebra'],
      'cat4': ['Science', 'Biology', 'Physics'],
      'course1_name': [
        'Intro to Web Design',
        'Algebra Basics',
        'Biology Foundations',
      ],
      'course1_meta': ['12 lessons · 6h 30m', '18 lessons · 4h 10m'],
      'course2_name': [
        'JavaScript Fundamentals',
        'Chemistry Basics',
        'Creative Writing',
      ],
      'course2_meta': ['24 lessons · 8h 41m', '9 lessons · 3h 05m'],
    },
  ),
  AppTypeEntry(
    'pos',
    'Shop Till / Sales Point',
    ['Register sale', 'Product list', 'Daily totals', 'Receipts'],
    templateId: 'pos',
    keywords: ['till', 'sales point', 'pos', 'cashier', 'register'],
    autoFields: {
      'owner_name': ['June', 'Peter', 'Sarah', 'Moses'],
      'shop_name': ['The Craft Shop', 'Corner Store', 'Netro Creative'],
      'today': ['Monday, 1 February', 'Today', 'Tuesday, 14 March'],
      'receipts': ['4', '19', '27'],
      'total_sales': ['362,290', '1,240,000', '86,400'],
      'menu_label': ['Menu', 'Products', 'Stock'],
    },
  ),
  AppTypeEntry(
    'social',
    'Community / Social App',
    ['Feed', 'Groups', 'Discover', 'Profile'],
    templateId: 'social',
    keywords: ['social', 'community', 'feed'],
    autoFields: {
      'community_tag': [
        'Community & Culture',
        'Made for creators',
        'Connect and share',
      ],
      'tab1': ['Following', 'For you', 'Trending'],
      'tab2': ['Discover', 'Nearby', 'Popular'],
      'tab3': ['Groups', 'Events', 'Saved'],
      'post1_title': [
        'Culture Festival Highlights',
        'Market Day Recap',
        'Sunset Over the Hills',
      ],
      'post1_author': ['Amara K.', 'Kwame O.', 'Zanele M.'],
      'post1_likes': ['1.5K', '820', '2.3K'],
      'post2_title': [
        'DIY Traditional Fashion',
        'Weekend Craft Fair',
        'New Fabric Drop',
      ],
      'post2_author': ['Tendai M.', 'Aisha B.', 'Kofi A.'],
      'post2_likes': ['183K', '4.2K', '9.6K'],
      'post3_title': [
        'A Map of Our Roots',
        'Where We Come From',
        'Community Stories',
      ],
      'post3_author': ['Chidi N.', 'Fatima Y.', 'Noma S.'],
      'post3_likes': ['100K', '15K', '6.8K'],
      'post4_title': [
        'My First Vlog',
        'Behind the Scenes',
        'A Day in the Village',
      ],
      'post4_author': ['Nia F.', 'Emeka T.', 'Layla R.'],
      'post4_likes': ['2.7M', '340K', '58K'],
    },
  ),
  AppTypeEntry(
    'eduplatform',
    'Course Marketplace App',
    ['Course catalog', 'Mentor profiles', 'Lesson progress', 'Enroll'],
    templateId: 'eduplatform',
    keywords: ['course marketplace', 'marketplace', 'mentor'],
    autoFields: {
      'course1_name': [
        'Figma Master Class for Beginners',
        'Intro to Bootstrap',
        'UI/UX Fundamentals',
      ],
      'course1_tutor': ['Trolentik Korlen', 'Jane Achan', 'Marlin Reyes'],
      'course1_due': ['28 lessons', 'Due Nov 2', '6h 30m'],
      'course1_level': ['Beginner', 'Intermediate'],
      'course2_name': [
        'Web Design Fundamentals',
        'JavaScript Basics',
        'Graphic Design Pro',
      ],
      'course2_tutor': ['Simons Lee', 'Peter Okot', 'Jesica Nabb'],
      'course2_due': ['24 lessons', 'Due Nov 9', '8h 20m'],
      'course2_level': ['Intermediate', 'Beginner'],
      'course3_name': [
        'App Development',
        'Prototype with Figma',
        'Mobile UI Essentials',
      ],
      'course3_tutor': ['Marlin Torres', 'Grace Auma', 'David Oduya'],
      'course3_due': ['15 lessons', 'Due Nov 16', '46 min'],
      'course3_level': ['Advanced', 'Beginner'],
      'mentor1_name': ['Marlin', 'Grace', 'David'],
      'mentor1_subject': ['UI/UX Design', 'Mathematics', 'Web Design'],
      'mentor2_name': ['Simons', 'Peter', 'Jesica'],
      'mentor2_subject': ['Web Design', 'Physics', 'Graphic Design'],
      'mentor3_name': ['Jesica', 'David', 'Simons'],
      'mentor3_subject': ['UI/UX Design', 'App Dev', 'Illustration'],
    },
  ),
  AppTypeEntry(
    'orders',
    'Order Pipeline App',
    ['Order stages', 'Revenue chart', 'Client details', 'Notifications'],
    templateId: 'orders',
    keywords: ['order pipeline', 'pipeline', 'orders'],
    autoFields: {
      'stage1_name': ['Leads', 'New enquiries', 'Quotes sent'],
      'stage1_count': ['4', '9', '6'],
      'stage1_new': ['2', '3', '1'],
      'stage2_name': [
        'Paid — Ready to Start',
        'Confirmed orders',
        'Deposit received',
      ],
      'stage2_count': ['23', '14', '31'],
      'stage2_new': ['3', '2', '5'],
      'stage3_name': ['In Progress', 'In Tailoring', 'Being Prepared'],
      'stage3_count': ['4', '7', '3'],
      'stage3_new': ['1', '2', '1'],
      'stage4_name': ['Ready to Send', 'Waiting for Feedback', 'Completed'],
      'stage4_count': ['3', '8', '12'],
      'revenue_total': ['\$3,780,113', '\$1,240,500', '\$842,900'],
      'revenue_today': ['\$604,355', '\$92,300', '\$38,600'],
    },
  ),
  AppTypeEntry(
    'products',
    'Product & Sales Tracker',
    ['Product list', 'Sales chart', 'Stock levels', 'Add product'],
    templateId: 'products',
    keywords: ['sales tracker', 'product tracker', 'inventory'],
    autoFields: {
      'owner_role': ['Owner', 'Shop Manager', 'Store Admin'],
      'product_count': ['6', '18', '42'],
      'sales_count': ['19', '54', '112'],
      'revenue': ['\$224', '\$1,840', '\$6,200'],
      'returns': ['4', '2', '9'],
      'chart_title': ["Today's sales", 'This week', 'Hourly sales'],
      'product1_name': [
        'Black Shine Shampoo',
        'Sunsilk Conditioner',
        'Herbal Soap Bar',
      ],
      'product1_stock': ['340', '88', '210'],
      'product1_price': ['699', '850', '250'],
      'product2_name': [
        'Gaming Headphone',
        'Wireless Earbuds',
        'Bluetooth Speaker',
      ],
      'product2_stock': ['88', '15,888', '46'],
      'product2_price': ['1000', '15888', '1200'],
      'product3_name': ['Daily Soap', 'Body Lotion', 'Hand Sanitizer'],
      'product3_stock': ['150', '60', '300'],
      'product3_price': ['699', '450', '150'],
    },
  ),
];

AppTypeEntry? appTypeById(String id) {
  for (final t in kAppTypes) {
    if (t.id == id) return t;
  }
  return null;
}
