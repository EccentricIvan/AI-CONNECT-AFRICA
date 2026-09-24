import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../ai_core/providers/ai_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_locale.dart';
import '../../shared/coding/code_autocorrect.dart' show CodeAutocorrectKind;
import '../../shared/coding/code_instruction_edit.dart';
import '../../shared/coding/interactive_html.dart' show escapeHtml;
import '../../shared/widgets/code_instruction_bar.dart';
import '../../shared/widgets/html_preview.dart';
import '../create/dev_l10n.dart';
import '../settings/coder_package_prompt.dart';
import 'site_build_coder.dart';

class _Template {
  const _Template(this.id, this.name, this.icon, this.askFields, this.autoFields);
  final String id, name;
  final IconData icon;
  final List<_QField> askFields;
  final Map<String, List<String>> autoFields;
}

class _QField {
  const _QField(this.key, this.question, this.hint);
  final String key, question, hint;
}

final _rng = Random();
String _pick(List<String> options) => options[_rng.nextInt(options.length)];

final _templates = [
  const _Template('bakery', '🍞 Bakery / Restaurant', Icons.bakery_dining, [
    _QField('business_name', "What's the name of your business?", 'e.g. Sweet Treats Bakery'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Your address?", 'e.g. Plot 15, Main Street, Kampala'),
  ], {
    'tagline': ['Fresh baked daily with love', 'Where every bite tells a story', 'Baking happiness since day one', 'The sweetest spot in town'],
    'description': ['We bake fresh bread, cakes, and pastries every morning using locally sourced ingredients. Visit us for the best treats in town!', 'Homemade goodness from our kitchen to your table. Fresh ingredients, traditional recipes, and a whole lot of love.', 'From artisan breads to custom cakes, we bring you the finest baked goods made fresh daily.'],
    'about': ['Started by a family passionate about baking. Every item is made from scratch with premium ingredients.', 'What started as a small kitchen dream has grown into the community\'s favourite bakery. We believe in quality, freshness, and making people smile.', 'Born from a love of traditional baking, we combine classic recipes with modern flavours to create unforgettable treats.'],
  }),
  const _Template('hotel', '🏨 Hotel / Lodge', Icons.hotel, [
    _QField('hotel_name', "Hotel name?", 'e.g. Grand Savanna Hotel'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Address?", 'e.g. Plot 45, Kampala Road'),
  ], {
    'tagline': ['Luxury meets African hospitality', 'Your home away from home', 'Where comfort meets elegance', 'Experience world-class hospitality'],
    'description': ['A premier luxury hotel offering world-class accommodation with stunning views and exceptional service.', 'Discover unparalleled comfort and hospitality in the heart of the city. Every stay is an experience to remember.', 'Where modern luxury meets warm African hospitality. Relax, unwind, and let us take care of every detail.'],
    'price_standard': ['150,000 UGX', '120,000 UGX', '180,000 UGX', '200,000 UGX'],
    'price_deluxe': ['350,000 UGX', '300,000 UGX', '400,000 UGX', '450,000 UGX'],
    'price_presidential': ['800,000 UGX', '750,000 UGX', '1,000,000 UGX', '900,000 UGX'],
    'email': ['reservations@hotel.com', 'info@hotel.com', 'bookings@hotel.com'],
  }),
  const _Template('fitness', '💪 Gym / Fitness', Icons.fitness_center, [
    _QField('gym_name', "Gym name?", 'e.g. Iron Forge Fitness'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Address?", 'e.g. Plot 12, Kampala'),
  ], {
    'tagline': ['Forge your best self', 'Stronger every day', 'No excuses. Just results.', 'Your fitness journey starts here'],
    'description': ['A modern fitness center with top equipment, expert trainers, and a motivating atmosphere for all fitness levels.', 'State-of-the-art equipment, certified personal trainers, and a community that pushes you to be your best.', 'From beginners to athletes, we provide the tools, space, and motivation to transform your body and mind.'],
    'price_basic': ['80,000 UGX', '60,000 UGX', '100,000 UGX', '75,000 UGX'],
    'price_premium': ['150,000 UGX', '180,000 UGX', '200,000 UGX', '160,000 UGX'],
    'price_student': ['50,000 UGX', '40,000 UGX', '45,000 UGX', '55,000 UGX'],
    'hours': ['Mon-Sat: 5AM-10PM, Sun: 7AM-6PM', 'Open daily: 5AM-11PM', 'Mon-Fri: 5AM-10PM, Weekends: 6AM-8PM'],
  }),
  const _Template('salon', '💇 Salon / Spa', Icons.spa, [
    _QField('salon_name', "Salon name?", 'e.g. Glow Beauty Salon'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Address?", 'e.g. Plot 8, Acacia Avenue'),
  ], {
    'tagline': ['Where beauty meets elegance', 'Unleash your inner glow', 'Beauty is our passion', 'Look good. Feel amazing.'],
    'description': ['A premium beauty salon offering hair, nails, facials, and makeup services in a relaxing atmosphere.', 'Step into luxury. Our expert team delivers stunning transformations in a serene, welcoming environment.', 'From everyday glam to special occasions, we help you look and feel your absolute best.'],
    'about': ['Expert stylists with 10+ years experience using premium products in a relaxing, modern space.', 'Our team of certified beauty professionals is passionate about helping you discover your most confident self.', 'We believe everyone deserves to feel beautiful. That\'s why we use only the finest products and techniques.'],
    'price_hair': ['30,000 UGX', '25,000 UGX', '35,000 UGX', '40,000 UGX'],
    'price_nails': ['25,000 UGX', '20,000 UGX', '30,000 UGX', '15,000 UGX'],
    'price_facial': ['40,000 UGX', '35,000 UGX', '50,000 UGX', '45,000 UGX'],
    'price_makeup': ['50,000 UGX', '60,000 UGX', '45,000 UGX', '70,000 UGX'],
    'hours_weekday': ['8AM - 7PM', '9AM - 8PM', '8AM - 6PM'],
    'hours_saturday': ['8AM - 8PM', '9AM - 9PM', '8AM - 6PM'],
    'hours_sunday': ['10AM - 5PM', 'Closed', '11AM - 4PM', '10AM - 3PM'],
  }),
  const _Template('church', '⛪ Church / Ministry', Icons.church, [
    _QField('church_name', "Church name?", 'e.g. Grace Community Church'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Address?", 'e.g. Plot 20, Jinja Road'),
  ], {
    'motto': ['Faith, Hope, and Love', 'Growing together in Christ', 'One family, one faith', 'Rooted in love, reaching the world'],
    'description': ['A welcoming community of believers growing together in faith, serving our community with love.', 'A vibrant, Spirit-filled church where everyone is welcome. Come as you are and experience God\'s love.', 'We exist to know God, grow in faith, and make a difference in our community and beyond.'],
    'verse': ['For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you.', 'Trust in the Lord with all your heart and lean not on your own understanding.', 'I can do all things through Christ who strengthens me.', 'The Lord is my shepherd; I shall not want.'],
    'verse_ref': ['Jeremiah 29:11', 'Proverbs 3:5', 'Philippians 4:13', 'Psalm 23:1'],
    'time_sunday': ['9:00 AM & 11:00 AM', '8:30 AM & 10:30 AM', '10:00 AM', '9:00 AM, 11:00 AM & 2:00 PM'],
    'time_bible': ['Wednesday 6:00 PM', 'Thursday 6:30 PM', 'Tuesday 7:00 PM'],
    'time_youth': ['Friday 5:00 PM', 'Saturday 3:00 PM', 'Friday 6:00 PM'],
    'email': ['info@church.org', 'welcome@church.org', 'office@church.org'],
  }),
  const _Template('realtor', '🏠 Real Estate', Icons.house, [
    _QField('company_name', "Company name?", 'e.g. Prime Properties'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Office address?", 'e.g. Plot 5, Bombo Road'),
  ], {
    'tagline': ['Finding your perfect home', 'Your trusted property partner', 'Dream homes made real', 'Where every home has a story'],
    'description': ['Uganda\'s trusted real estate agency helping families find their dream homes for over 10 years.', 'Professional property services — buying, selling, and renting across the city and beyond.', 'We make finding your perfect property simple, transparent, and stress-free.'],
    'prop1_name': ['Modern Villa in Munyonyo', 'Lakeside Mansion', 'Executive Home in Buziga', 'Luxury Villa in Entebbe'],
    'prop1_beds': ['4', '5', '3', '6'], 'prop1_baths': ['3', '4', '2', '5'],
    'prop1_size': ['2,500 sqft', '3,200 sqft', '2,800 sqft', '4,000 sqft'],
    'prop1_price': ['450M UGX', '600M UGX', '380M UGX', '750M UGX'],
    'prop1_location': ['Munyonyo, Kampala', 'Buziga, Kampala', 'Entebbe', 'Muyenga, Kampala'],
    'prop2_name': ['Apartment in Kololo', 'City Penthouse', 'Studio in Nakasero', 'Garden Apartment'],
    'prop2_beds': ['2', '3', '1', '2'], 'prop2_baths': ['2', '2', '1', '2'],
    'prop2_size': ['1,200 sqft', '1,500 sqft', '800 sqft', '1,100 sqft'],
    'prop2_price': ['180M UGX', '250M UGX', '120M UGX', '200M UGX'],
    'prop2_location': ['Kololo, Kampala', 'Nakasero, Kampala', 'Bugolobi', 'Naguru'],
    'prop3_name': ['Family Home in Ntinda', 'Suburban House', 'Townhouse in Kira', 'Bungalow in Naalya'],
    'prop3_beds': ['3', '4', '3', '3'], 'prop3_baths': ['2', '3', '2', '2'],
    'prop3_size': ['1,800 sqft', '2,200 sqft', '1,600 sqft', '2,000 sqft'],
    'prop3_price': ['280M UGX', '320M UGX', '240M UGX', '300M UGX'],
    'prop3_location': ['Ntinda, Kampala', 'Kira, Wakiso', 'Naalya', 'Kyanja, Kampala'],
    'properties_sold': ['500+', '300+', '750+', '400+'],
    'years_exp': ['12', '8', '15', '10'],
    'clients': ['1,200+', '800+', '2,000+', '950+'],
    'email': ['info@properties.ug', 'sales@realestate.ug', 'hello@homes.ug'],
  }),
  const _Template('techstartup', '🚀 Tech Startup', Icons.rocket_launch, [
    _QField('company_name', "Company name?", 'e.g. NexaFlow'),
    _QField('email', "Contact email?", 'e.g. hello@company.io'),
  ], {
    'tagline': ['Simplify everything. Build anything.', 'Technology that works for you.', 'The future, delivered today.', 'Smart solutions. Real results.'],
    'feat1_title': ['Lightning Fast', 'Blazing Speed', 'Instant Performance'], 'feat1_desc': ['Built for speed. Our platform loads in under 1 second.', 'Optimized for performance — no waiting, no lag, just results.'],
    'feat2_title': ['Bank-Level Security', 'Enterprise Security', 'Ironclad Protection'], 'feat2_desc': ['End-to-end encryption protects your data at all times.', '256-bit encryption and SOC 2 compliance keep your data safe.'],
    'feat3_title': ['Easy Integration', 'Plug & Play', 'Seamless Connect'], 'feat3_desc': ['Connect with 100+ tools your team already uses.', 'Works with your existing tools — no migration headaches.'],
    'feat4_title': ['Global Scale', 'Built to Scale', 'Worldwide Reach'], 'feat4_desc': ['Serve millions of users across every continent.', 'From 10 users to 10 million — our infrastructure grows with you.'],
    'stat_users': ['50K+', '25K+', '100K+', '75K+'],
    'stat_countries': ['30+', '45+', '20+', '60+'],
    'stat_uptime': ['99.9%', '99.99%', '99.95%'],
    'cta_text': ['Join thousands of teams already building better products faster.', 'Start free today — no credit card required. See results in minutes.', 'Ready to transform your workflow? Get started in 60 seconds.'],
  }),
  const _Template('ngo', '🌍 NGO / Charity', Icons.volunteer_activism, [
    _QField('org_name', "Organization name?", 'e.g. Hope Foundation'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Office address?", 'e.g. Plot 15, Buganda Road'),
  ], {
    'tagline': ['Building brighter futures together', 'Every life matters', 'Empowering communities, changing lives', 'Together we make a difference'],
    'mission_title': ['Our Mission', 'What We Do', 'Why We Exist'],
    'mission': ['Empowering communities through education, healthcare, and sustainable development across East Africa.', 'Creating lasting change by investing in education, clean water, and economic opportunity for underserved communities.', 'We believe every person deserves access to education, healthcare, and opportunity — and we work to make it happen.'],
    'impact1_num': ['15,000+', '20,000+', '8,000+', '12,000+'], 'impact1_label': ['Lives Changed', 'People Reached', 'Lives Impacted'],
    'impact2_num': ['50+', '35+', '80+', '25+'], 'impact2_label': ['Communities', 'Villages Served', 'Partner Schools'],
    'impact3_num': ['8', '12', '5', '15'], 'impact3_label': ['Years Active', 'Years of Impact', 'Years Serving'],
    'prog1_name': ['Education for All', 'School Access Program', 'Scholarship Initiative'],
    'prog1_desc': ['Scholarships and school supplies for children in rural communities.', 'Building schools and training teachers in underserved areas.'],
    'prog2_name': ['Clean Water Initiative', 'Health & Wellness', 'Community Health'],
    'prog2_desc': ['Building wells and water purification systems in villages.', 'Mobile health clinics bringing healthcare to remote communities.'],
    'prog3_name': ['Youth Skills Training', 'Economic Empowerment', 'Women\'s Enterprise'],
    'prog3_desc': ['Teaching digital skills, tailoring, and agriculture to young people.', 'Microloans and business training for women entrepreneurs.'],
    'donate_text': ['Every contribution helps us reach more communities. Together we can make a lasting difference.', 'Your support changes lives. 100% of donations go directly to our programs.'],
    'email': ['info@foundation.org', 'donate@charity.org', 'hello@ngo.org'],
  }),
  const _Template('portfolio', '👤 Personal Portfolio', Icons.person, [
    _QField('name', "What's your name?", 'e.g. Alice Nakamya'),
    _QField('title', "Your title or role?", 'e.g. Student Developer'),
    _QField('email', "Your email?", 'e.g. alice@example.com'),
  ], {
    'about': ['A passionate developer building websites and apps that solve real problems.', 'Creative problem-solver with a love for clean code and beautiful design.', 'Self-taught developer on a mission to build technology that makes a difference.'],
    'skill1': ['HTML & CSS', 'Web Design', 'UI/UX Design'],
    'skill2': ['JavaScript', 'React', 'TypeScript'],
    'skill3': ['Python', 'Data Analysis', 'Machine Learning'],
    'skill4': ['Flutter', 'Mobile Development', 'Dart'],
    'skill5': ['UI Design', 'Figma', 'Problem Solving'],
    'project1_name': ['School Website', 'E-commerce Store', 'Blog Platform'],
    'project1_desc': ['Built a responsive website with student portal and events.', 'Online store with cart, checkout, and payment integration.'],
    'project2_name': ['Weather App', 'Task Manager', 'Chat Application'],
    'project2_desc': ['Mobile app showing real-time weather with beautiful animations.', 'Productivity app with reminders, categories, and sync.'],
    'project3_name': ['Quiz Game', 'Budget Tracker', 'Recipe Finder'],
    'project3_desc': ['Interactive quiz testing knowledge across multiple subjects.', 'Personal finance app tracking income, expenses, and savings.'],
    'phone': ['+256 700 123 456', '+256 770 456 789', '+256 780 234 567'],
    'location': ['Kampala, Uganda', 'Nairobi, Kenya', 'Dar es Salaam, Tanzania'],
  }),
  const _Template('school', '🎓 School Website', Icons.school, [
    _QField('school_name', "School name?", 'e.g. Bright Future Academy'),
    _QField('phone', "School phone?", 'e.g. +256 700 123 456'),
    _QField('address', "School address?", 'e.g. Plot 23, Education Road'),
  ], {
    'motto': ['Excellence Through Education', 'Building Tomorrow\'s Leaders', 'Knowledge, Integrity, Service', 'Where Futures Begin'],
    'description': ['A leading institution providing quality education from primary through secondary level.', 'Nurturing young minds with academic excellence, character development, and practical skills for the future.', 'Where every student is empowered to discover their potential and make a positive impact on the world.'],
    'students': ['850', '1,200', '600', '950'],
    'teachers': ['45', '60', '35', '52'],
    'years': ['15', '25', '10', '20'],
    'pass_rate': ['92%', '88%', '95%', '90%'],
    'email': ['info@school.ac.ug', 'admissions@academy.ac.ug', 'office@school.edu'],
  }),
  const _Template('agritech', '🌱 Farm / Agribusiness', Icons.agriculture, [
    _QField('business_name', "What's the name of your farm or agribusiness?", 'e.g. Green Valley Farms'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
    _QField('address', "Where are your fields?", 'e.g. Mukono District, Uganda'),
  ], {
    'tagline': ['Your farm, smarter.', 'Growing more with less', 'Smart farming for better harvests', 'From our soil to your table'],
    'description': ['We monitor crop health, manage water use, and plan every season with data — so every hectare produces more.', 'A modern farm using soil data, weather tracking, and careful planning to grow healthy, high-yield crops all year round.', 'Empowering our community with sustainable farming practices, quality produce, and fair prices for every harvest.'],
    'total_fields': ['12', '24', '8', '16'],
    'total_area': ['45 acres', '125 acres', '30 acres', '60 acres'],
    'yield_amount': ['15 tons', '22 tons', '9 tons', '30 tons'],
    'health_score': ['86/100', '92/100', '78/100', '88/100'],
    'crop1': ['🌽 Maize', '🌾 Rice', '☕ Coffee', '🍌 Matooke'],
    'crop2': ['🫘 Beans', '🥜 Groundnuts', '🍠 Sweet potato', '🌻 Sunflower'],
    'crop3': ['🥬 Vegetables', '🍅 Tomatoes', '🥕 Carrots', '🌶️ Chilli'],
    'soil_note': ['Healthy', 'Good', 'Improving'],
    'season_note': ['On target', 'Strong', 'Above average'],
    'email': ['info@farm.ug', 'harvest@agro.ug', 'hello@greenfields.ug'],
  }),
  const _Template('saasai', '🤖 AI / Software Product', Icons.auto_awesome, [
    _QField('company_name', "Company or product name?", 'e.g. Optivize AI'),
    _QField('email', "Contact email?", 'e.g. hello@company.io'),
  ], {
    'pill_text': ['Your all-in-one AI platform', 'Built for growing teams', 'Automation that just works'],
    'tagline': ['Supercharge your business with AI-powered automation', 'Smarter decisions, made automatic', 'Do more, with far less busywork', 'The AI workspace your team deserves'],
    'description': ['Our platform helps teams save time, cut costs, and unlock smarter decision-making — without the complexity.', 'Automate the repetitive work, surface the insights that matter, and give your team back hours every week.', 'Everything your team needs to plan, automate, and measure — in one calm, fast workspace.'],
    'stat1_value': ['12,500', '8,400', '20,000'],
    'stat1_label': ['Daily tasks automated for our customers'],
    'stat2_value': ['\$480,000', '\$250,000', '\$1.2M'],
    'stat2_label': ['Cost savings generated for clients'],
    'stat3_value': ['150K+', '80K+', '210K+'],
    'stat3_label': ['Users across 40+ countries'],
    'stat4_value': ['98%', '99.9%', '96%'],
    'stat4_label': ['Predictions validated against real data'],
    'feat1_title': ['Lightning fast', 'Instant setup', 'Built for speed'],
    'feat1_desc': ['Loads in under a second and never makes your team wait on a spinner.', 'Connect your tools and see results in minutes, not months.'],
    'feat2_title': ['Bank-level security', 'Private by default', 'Enterprise ready'],
    'feat2_desc': ['End-to-end encryption keeps every record safe, on every device.', 'Your data stays yours — encrypted in transit and at rest, always.'],
    'feat3_title': ['Works with your tools', 'Easy integration', 'Fits your workflow'],
    'feat3_desc': ['Connects to the apps your team already uses — no migration headaches.', 'Plug it in alongside what you have and keep working the way you like.'],
    'cta_text': ['Join thousands of teams already building better products, faster.', 'Start free today — no card needed. See results in your first week.', 'Ready to cut the busywork? Get set up in under five minutes.'],
  }),
  const _Template('taskflow', '✅ Productivity / SaaS Tool', Icons.checklist_rounded, [
    _QField('company_name', "Product name?", 'e.g. TaskFlow'),
    _QField('email', "Contact email?", 'e.g. hello@taskflow.app'),
    _QField('phone', "Phone number?", 'e.g. +256 700 123 456'),
  ], {
    'pill_text': ['New: AI task summaries', 'Now with shared goals', 'New: weekly auto-reports'],
    'tagline': ['The productivity OS for modern teams', 'One workspace for everything your team ships', 'Where scattered work finally comes together'],
    'description': ['Stop switching apps. Manage tasks, docs, and goals in one unified workspace designed for speed.', 'Plans, progress, and people in one place — so nobody has to ask what happened this week.', 'Everything your team is working on, visible at a glance, updated as the work happens.'],
    'trusted_count': ['5,000+', '2,400+', '10,000+'],
    'project_name': ['Product Launch Q4', 'Term 2 Rollout', 'Website Redesign', 'Field Team Sprint'],
    'metric1_value': ['78%', '64%', '91%'],
    'metric1_label': ['Total progress'],
    'metric2_value': ['12', '7', '23'],
    'metric2_label': ['Pending tasks'],
    'metric3_value': ['42h', '28h', '61h'],
    'metric3_label': ['Time tracked'],
    'task1': ['Update branding', 'Client meeting notes', 'Finalize budget'],
    'task2': ['Review submissions', 'Prepare demo', 'Draft newsletter'],
    'task3': ['Q4 budgeting', 'Team retro', 'Ship release notes'],
    'why_text': ['The difference is not just another tool. It is the difference between chaos and clarity — see how we change your daily grind.', 'Most teams lose hours every week to status-chasing. We give those hours back.'],
    'old_way': ['Updates scattered across chat, email, and three spreadsheets nobody trusts.', 'Endless status meetings just to find out what actually moved this week.'],
    'new_way': ['One shared board everybody updates as they work — always current, always visible.', 'Progress updates itself, so meetings become decisions instead of roll calls.'],
  }),
  const _Template('edudash', '📊 School Dashboard', Icons.insights, [
    _QField('school_name', "School name?", 'e.g. Bright Future Academy'),
    _QField('phone', "School phone?", 'e.g. +256 700 123 456'),
    _QField('address', "School address?", 'e.g. Plot 23, Education Road, Kampala'),
  ], {
    'motto': ['What do you want to learn today?', 'Building tomorrow\'s leaders', 'Excellence through education', 'Every learner, every day'],
    'description': ['Track progress, celebrate results, and keep every learner moving forward with clear, shared insight.', 'A complete picture of how our school is doing — attendance, coursework, and results in one place.', 'Nurturing young minds with academic excellence, character, and practical skills for the future.'],
    'students': ['3,500', '850', '1,200', '620'],
    'teachers': ['145', '45', '60', '38'],
    'courses': ['24', '12', '31', '18'],
    'pass_rate': ['92%', '88%', '95%', '90%'],
    'attendance': ['94%', '88%', '91%'],
    'coursework': ['72%', '81%', '66%'],
    'retention': ['63%', '78%', '85%'],
    'student1_name': ['Emily Carter', 'Aisha Nakato', 'Samuel Okello'],
    'student1_class': ['Senior 4', 'Primary 7', 'Senior 6'],
    'student2_name': ['Alex Johnson', 'Brian Mugisha', 'Grace Achieng'],
    'student2_class': ['Senior 3', 'Primary 6', 'Senior 5'],
    'student3_name': ['Sophia Martinez', 'Daniel Ssempa', 'Mercy Atim'],
    'student3_class': ['Senior 2', 'Primary 5', 'Senior 4'],
    'email': ['info@school.ac.ug', 'admissions@academy.ac.ug', 'office@school.edu'],
  }),
  const _Template('smartedu', '🎓 Student Portal', Icons.dashboard_customize, [
    _QField('school_name', "School or platform name?", 'e.g. Smart Learning'),
    _QField('phone', "Contact phone?", 'e.g. +256 700 123 456'),
    _QField('address', "Address?", 'e.g. Plot 12, Kampala'),
  ], {
    'greeting': ['Hello, welcome back!', 'Good to see you again!', 'Ready to learn today?'],
    'description': ['Track your attendance, homework, and classes — all in one place.', 'Your classes, teachers, and progress, at a glance.'],
    'student_name': ['Alex Parker', 'Grace Nabirye', 'Daniel Ochieng'],
    'attendance': ['90%', '85%', '95%'],
    'homework': ['70%', '60%', '80%'],
    'rating': ['75%', '68%', '82%'],
    'completed': ['40%', '55%', '35%'],
    'class1_name': ['Python Programming', 'Mathematics', 'English'],
    'class1_time': ['10:00 · 2/10 lessons', '9:00 · 5/12 lessons'],
    'class2_name': ['Data Science', 'Physics', 'Biology'],
    'class2_time': ['14:00 · 4/9 lessons', '11:00 · 3/8 lessons'],
    'class3_name': ['Artificial Intelligence', 'Chemistry', 'History'],
    'class3_time': ['10:00 · 8/8 lessons', '13:00 · 6/6 lessons'],
    'teacher1_name': ['Adam Potter', 'Grace Auma', 'John Kato'],
    'teacher1_initial': ['A', 'G', 'J'],
    'teacher1_subject': ['Python Programming', 'Mathematics', 'English'],
    'teacher2_name': ['Brian Green', 'Susan Nakato', 'Peter Owino'],
    'teacher2_initial': ['B', 'S', 'P'],
    'teacher2_subject': ['Data Science', 'Physics', 'Biology'],
    'teacher3_name': ['Peter Nelson', 'Mary Achan', 'James Mubiru'],
    'teacher3_initial': ['P', 'M', 'J'],
    'teacher3_subject': ['Artificial Intelligence', 'Chemistry', 'History'],
    'email': ['hello@smartlearning.ac.ug', 'info@school.edu', 'office@academy.ug'],
  }),
];

// ── Chat messages ────────────────────────────────────────────────────────────

class _ChatMsg {
  const _ChatMsg(this.text, this.isBot);
  final String text;
  final bool isBot;
}

// ── Screen ───────────────────────────────────────────────────────────────────

class SiteChatBuilderScreen extends ConsumerStatefulWidget {
  const SiteChatBuilderScreen({super.key});

  @override
  ConsumerState<SiteChatBuilderScreen> createState() =>
      _SiteChatBuilderScreenState();
}

class _SiteChatBuilderScreenState extends ConsumerState<SiteChatBuilderScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _codeController = TextEditingController();
  final _studioKey = GlobalKey<LiveHtmlStudioState>();
  final List<_ChatMsg> _messages = [];
  final Map<String, String> _answers = {};
  /// Auto-picked template copy, locked in before Build so the coder sees it.
  final Map<String, String> _recordedContent = {};

  _Template? _template;
  int _fieldIndex = -1;
  bool _choosingTemplate = true;
  bool _choosingColor = false;
  String _colorTheme = '';
  bool _building = false;
  bool _showStudio = false;
  String _buildNote = '';

  /// Code as it stood before the last AI change, so it can be reverted.
  String? _undoSnapshot;
  bool _autocorrectBusy = false;

  static const _colorThemes = {
    '1': {'name': 'Default', 'primary': null, 'bg': null},
    '2': {'name': 'Ocean Blue', 'primary': '#2563eb', 'bg': '#eff6ff'},
    '3': {'name': 'Forest Green', 'primary': '#059669', 'bg': '#ecfdf5'},
    '4': {'name': 'Royal Purple', 'primary': '#7c3aed', 'bg': '#f5f3ff'},
    '5': {'name': 'Sunset Orange', 'primary': '#ea580c', 'bg': '#fff7ed'},
    '6': {'name': 'Rose Pink', 'primary': '#e11d48', 'bg': '#fff1f2'},
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
  }

  Future<void> _startIntro() async {
    await _sayBot(
      "Hi! I'm going to help you build a website. 🚀\n\nWhat type of site do you want?",
    );
    await _sayBot(
      // Circled numerals, not keycap emoji: Unicode has no keycap for 11-15,
      // so those had to be spelled as two boxes (1️⃣1️⃣) and broke the column.
      // U+2460-U+246E is one glyph per number all the way to 15, so every row
      // starts at the same width.
      "① Bakery / Restaurant\n② Hotel / Lodge\n③ Gym / Fitness\n④ Salon / Spa\n⑤ Church / Ministry\n⑥ Real Estate\n⑦ Tech Startup\n⑧ NGO / Charity\n⑨ Personal Portfolio\n⑩ School Website\n⑪ Farm / Agribusiness\n⑫ AI / Software Product\n⑬ Productivity / SaaS Tool\n⑭ School Dashboard\n⑮ Student Portal\n\nJust type the number or name!",
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sayBot(String english) async {
    final shown = await localizeDevBot(ref, english);
    if (!mounted) return;
    setState(() => _messages.add(_ChatMsg(shown, true)));
    _scrollDown();
  }

  void _addUser(String text) {
    setState(() => _messages.add(_ChatMsg(text, false)));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _building) return;
    _controller.clear();
    _addUser(text);

    // Numbers/template names match in English; free-text answers stay as typed.
    final english = await localizeDevStudent(ref, text);
    if (!mounted) return;

    if (_choosingTemplate) {
      await _handleTemplateChoice(english);
    } else if (_choosingColor) {
      await _handleColorChoice(english);
    } else if (_fieldIndex >= 0 && _template != null) {
      await _handleFieldAnswer(text);
    }
  }

  Future<void> _handleColorChoice(String text) async {
    final lower = text.trim();
    String? key;
    for (final k in _colorThemes.keys) {
      if (lower.contains(k) ||
          lower
              .toLowerCase()
              .contains(_colorThemes[k]!['name']!.toLowerCase())) {
        key = k;
        break;
      }
    }
    key ??= '1';

    _colorTheme = key;
    _choosingColor = false;
    _fieldIndex = 0;

    final name = _colorThemes[key]!['name'];
    await _sayBot(
      "$name theme selected! ✨\n\nNow just ${_template!.askFields.length} quick questions:",
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _askCurrentField();
  }

  Future<void> _handleTemplateChoice(String text) async {
    final lower = text.toLowerCase();
    _Template? chosen;

    // A typed number wins outright. Substring matching cannot be used for
    // digits: "10" contains "1", so it would always resolve to template 1.
    final digits = RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(lower)?.group(1);
    final picked = digits == null ? null : int.tryParse(digits);
    if (picked != null && picked >= 1 && picked <= _templates.length) {
      chosen = _templates[picked - 1];
    }

    // Specific phrases first, so "school dashboard" cannot be eaten by "school".
    const matchers = <int, List<String>>{
      14: ['student portal', 'portal'],
      13: ['school dashboard', 'dashboard', 'admin panel'],
      10: ['farm', 'agri', 'crop', 'harvest', 'garden', 'produce'],
      12: ['productivity', 'task', 'project management', 'workspace', 'to-do app'],
      11: ['artificial intelligence', 'saas', 'automation', 'software product'],
      0: ['bakery', 'restaurant', 'food', 'cafe'],
      1: ['hotel', 'lodge', 'guest house', 'accommodation'],
      2: ['gym', 'fitness', 'workout'],
      3: ['salon', 'spa', 'beauty', 'hair'],
      4: ['church', 'ministry', 'chapel', 'worship'],
      5: ['real estate', 'property', 'realtor', 'house'],
      6: ['tech', 'startup', 'software'],
      7: ['ngo', 'charity', 'foundation', 'nonprofit'],
      8: ['portfolio', 'personal', 'resume', 'cv'],
      9: ['school', 'academy', 'college', 'education'],
    };

    if (chosen == null && lower.trim() == 'ai') {
      chosen = _templates[11];
    }

    if (chosen == null) {
      for (final entry in matchers.entries) {
        for (final keyword in entry.value) {
          if (lower.contains(keyword)) {
            chosen = _templates[entry.key];
            break;
          }
        }
        if (chosen != null) break;
      }
    }

    if (chosen == null) {
      await _sayBot(
        "I didn't catch that. Please type a number (1-15) or the name:\n\n1 Bakery  2 Hotel  3 Gym  4 Salon  5 Church\n6 Real Estate  7 Tech  8 NGO  9 Portfolio  10 School\n11 Farm  12 AI Product  13 Productivity  14 School Dashboard  15 Student Portal",
      );
      return;
    }

    _template = chosen;
    _choosingTemplate = false;
    _choosingColor = true;

    await _sayBot("Great choice — ${chosen.name}! 🎨\n\nPick a color theme:");
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _sayBot(
      "① Default (template colors)\n② Ocean Blue 🔵\n③ Forest Green 🟢\n④ Royal Purple 🟣\n⑤ Sunset Orange 🟠\n⑥ Rose Pink 🩷\n\nType a number!",
    );
  }

  Future<void> _askCurrentField() async {
    if (_template == null || _fieldIndex >= _template!.askFields.length) return;
    final field = _template!.askFields[_fieldIndex];
    await _sayBot("${field.question}\n\n💡 ${field.hint}");
  }

  Future<void> _handleFieldAnswer(String text) async {
    final field = _template!.askFields[_fieldIndex];
    final answer = text.trim();
    _answers[field.key] = answer;
    _fieldIndex++;

    if (_fieldIndex >= _template!.askFields.length) {
      _recordAutoContent();
      final recorded = tr(
        context,
        'Perfect! All features recorded. ✅ Building your site…',
      );
      setState(() => _messages.add(_ChatMsg(recorded, true)));
      _scrollDown();
      await _buildSite();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _askCurrentField();
    }
  }

  /// Lock auto-picked copy into the intent before the coder runs.
  void _recordAutoContent() {
    _recordedContent.clear();
    if (_template == null) return;
    for (final entry in _template!.autoFields.entries) {
      _recordedContent[entry.key] = _pick(entry.value);
    }
  }

  SiteBuildIntent _currentIntent() {
    final theme = _colorThemes[_colorTheme];
    return SiteBuildIntent(
      templateId: _template!.id,
      templateName: _template!.name,
      themeName: theme?['name'] ?? 'Default',
      themePrimary: theme?['primary'],
      answers: Map<String, String>.from(_answers),
      content: Map<String, String>.from(_recordedContent),
    );
  }

  /// Maps the learner's answers + recorded copy onto the matching static
  /// template. Every value is HTML-escaped — a `<` or `&` typed into a
  /// business name or phone number must render as text, not markup.
  Future<String> _assembleTemplateHtml(SiteBuildIntent intent) async {
    var html =
        await rootBundle.loadString('assets/templates/${intent.templateId}.html');
    for (final e in intent.answers.entries) {
      html = html.replaceAll('{{${e.key}}}', escapeHtml(e.value));
    }
    for (final e in intent.content.entries) {
      html = html.replaceAll('{{${e.key}}}', escapeHtml(e.value));
    }
    if (intent.themePrimary != null) {
      final colorCSS =
          '<style>:root{--primary:${intent.themePrimary}} '
          'header,nav,.btn,[class*=hero]{background:${intent.themePrimary}!important} '
          '.btn{background:${intent.themePrimary}!important}</style>';
      html = html.replaceFirst('</head>', '$colorCSS</head>');
    }
    return html;
  }

  void _applyCodeEdits() {
    // LiveHtmlStudio already mirrors the controller; this keeps a hard refresh hook.
    setState(() {});
  }

  Future<void> _undoLastInstruction() async {
    final previous = _undoSnapshot;
    if (previous == null) return;
    _undoSnapshot = null;
    _codeController.text = previous;
    _studioKey.currentState?.applyNow();
  }

  /// Runs a free-form instruction ("center the text", "change color to
  /// blue") through the coder model and, on success, repaints the preview
  /// immediately — no separate manual "Apply" tap needed for an AI edit.
  Future<void> _applyInstruction(String instruction) async {
    if (_autocorrectBusy) return;
    final before = _codeController.text;
    if (before.trim().isEmpty) return;
    final coderOk = await promptAndFetchCoderPackage(context, ref);
    if (!coderOk || !mounted) return;
    setState(() => _autocorrectBusy = true);
    try {
      final engine = await ref.read(programmingEngineProvider.future);
      final fixed = await applyCodeInstruction(
        source: before,
        instruction: instruction,
        kind: CodeAutocorrectKind.html,
        engine: engine,
      );
      if (!mounted) return;
      if (fixed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, "Couldn't apply that — try describing it a different way."),
            ),
          ),
        );
        return;
      }
      _undoSnapshot = before;
      _codeController.text = fixed;
      _studioKey.currentState?.applyNow();
      if (!mounted) return;
      showInstructionAppliedSnack(context, onUndo: _undoLastInstruction);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Something went wrong. Please try again.'))),
      );
    } finally {
      if (mounted) setState(() => _autocorrectBusy = false);
    }
  }

  /// Deterministic build: map the learner's answers straight onto the
  /// matching static template — no LLM on this path, so it paints in
  /// milliseconds and always renders (the coding model is only ever an
  /// optional, explicit follow-up via the Autocorrect button in the code
  /// view, never a gate on seeing a working preview).
  Future<void> _buildSite() async {
    if (_template == null) return;
    if (!mounted) return;

    setState(() {
      _building = true;
      _buildNote = tr(context, 'Building your site…');
    });

    final intent = _currentIntent();
    final html = await _assembleTemplateHtml(intent);

    if (!mounted) return;
    _codeController.text = html;

    final ready = tr(
      context,
      'Your website is ready! 🎉 Toggle Preview / Code to view or edit.',
    );

    setState(() {
      _messages.add(_ChatMsg(ready, true));
      _building = false;
      _showStudio = true;
      _buildNote = '';
    });
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.language, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          // Flexible + ellipsis: a longer translation (e.g. Luganda) plus
          // the two action buttons beside it can exceed the AppBar's title
          // width by a couple of pixels — pre-existing, only surfaced now
          // that this screen is actually reachable under those languages.
          Flexible(
            child: Text(
              tr(context, 'Website Builder'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => context.push('/website'),
            child: Text(tr(context, 'Block canvas')),
          ),
          if (_showStudio)
            TextButton(
              onPressed: () => setState(() => _showStudio = false),
              child: Text(tr(context, 'Back to chat')),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Text(
              tr(
                context,
                _showStudio
                    ? 'Edit the code on the left — the preview on the right updates as you type. Use Reload or Full screen in the preview bar.'
                    : 'Pick a site type and features — your site builds instantly '
                        'from a professional template, then opens Preview Layout | '
                        'View Source Code. Want the coding model to refine the code? '
                        'Use Autocorrect from the code view.',
              ),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),

          if (_showStudio) ...[
            Expanded(
              child: LiveHtmlStudio(
                key: _studioKey,
                controller: _codeController,
                onApply: _applyCodeEdits,
                toolbar: CodeInstructionBar(
                  busy: _autocorrectBusy,
                  onSubmit: _applyInstruction,
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final msg = _messages[i];
                  return _ChatBubble(text: msg.text, isBot: msg.isBot);
                },
              ),
            ),
          ],

          if (_building)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _buildNote.isEmpty
                          ? tr(context, 'Building your site...')
                          : _buildNote,
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),

          if (!_showStudio && !_building)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _onSend(),
                      decoration: InputDecoration(
                        hintText: _choosingTemplate
                            ? tr(context, 'Type 1–10 or a site name…')
                            : tr(context, 'Type your answer...'),
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _onSend,
                    icon: const Icon(Icons.arrow_upward),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Chat bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.isBot});
  final String text;
  final bool isBot;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isBot
              ? Theme.of(context).colorScheme.surface
              : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isBot ? 4 : 16),
            topRight: Radius.circular(isBot ? 16 : 4),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
          border: isBot ? Border.all(color: Theme.of(context).dividerColor) : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isBot ? Theme.of(context).colorScheme.onSurface : Colors.white,
            height: 1.5,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

