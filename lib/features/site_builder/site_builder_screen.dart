import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/studio_page.dart';

class _TemplateInfo {
  const _TemplateInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.fields,
  });
  final String id, name, description;
  final IconData icon;
  final Color color;
  final List<_Field> fields;
}

class _Field {
  const _Field(this.key, this.label, this.hint, {this.defaultValue = ''});
  final String key, label, hint, defaultValue;
}

const _templates = [
  _TemplateInfo(
    id: 'bakery',
    name: 'Bakery / Restaurant',
    icon: Icons.bakery_dining,
    color: Color(0xFFB45309),
    description: 'Menu, about, and contact for a food business',
    fields: [
      _Field('business_name', 'Business Name', 'e.g. Sweet Treats Bakery', defaultValue: 'Sweet Treats Bakery'),
      _Field('tagline', 'Tagline', 'e.g. Fresh baked daily since 2020', defaultValue: 'Fresh baked daily with love'),
      _Field('description', 'Description', 'What makes your bakery special?', defaultValue: 'We bake fresh bread, cakes, and pastries every morning using locally sourced ingredients. Visit us for the best treats in town!'),
      _Field('about', 'About', 'Your story', defaultValue: 'Started in 2020 by a family passionate about baking. Every item is made from scratch with premium ingredients and lots of love.'),
      _Field('address', 'Address', 'Your location', defaultValue: 'Plot 15, Main Street, Kampala'),
      _Field('phone', 'Phone', 'Your phone number', defaultValue: '+256 700 123 456'),
    ],
  ),
  _TemplateInfo(
    id: 'portfolio',
    name: 'Personal Portfolio',
    icon: Icons.person,
    color: AppColors.primaryLight,
    description: 'Showcase your skills, projects, and contact',
    fields: [
      _Field('name', 'Your Name', 'e.g. Alice Nakamya', defaultValue: 'Alice Nakamya'),
      _Field('title', 'Title', 'e.g. Web Developer & Designer', defaultValue: 'Student Developer & Designer'),
      _Field('about', 'About Me', 'Tell your story', defaultValue: 'I am a passionate student developer learning to build websites and mobile apps. I love solving problems with code and creating beautiful user experiences.'),
      _Field('skill1', 'Skill 1', '', defaultValue: 'HTML & CSS'),
      _Field('skill2', 'Skill 2', '', defaultValue: 'JavaScript'),
      _Field('skill3', 'Skill 3', '', defaultValue: 'Python'),
      _Field('skill4', 'Skill 4', '', defaultValue: 'Flutter'),
      _Field('skill5', 'Skill 5', '', defaultValue: 'UI Design'),
      _Field('project1_name', 'Project 1 Name', '', defaultValue: 'School Website'),
      _Field('project1_desc', 'Project 1 Description', '', defaultValue: 'Built a responsive website for my school with student portal and event calendar.'),
      _Field('project2_name', 'Project 2 Name', '', defaultValue: 'Weather App'),
      _Field('project2_desc', 'Project 2 Description', '', defaultValue: 'A mobile app that shows weather forecasts with beautiful animations.'),
      _Field('project3_name', 'Project 3 Name', '', defaultValue: 'Quiz Game'),
      _Field('project3_desc', 'Project 3 Description', '', defaultValue: 'An interactive quiz game testing knowledge across multiple subjects.'),
      _Field('email', 'Email', '', defaultValue: 'alice@example.com'),
      _Field('phone', 'Phone', '', defaultValue: '+256 700 123 456'),
      _Field('location', 'Location', '', defaultValue: 'Kampala, Uganda'),
    ],
  ),
  _TemplateInfo(
    id: 'school',
    name: 'School Website',
    icon: Icons.school,
    color: Color(0xFF3B82F6),
    description: 'Programs, values, stats, and enrollment',
    fields: [
      _Field('school_name', 'School Name', 'e.g. Bright Future Academy', defaultValue: 'Bright Future Academy'),
      _Field('motto', 'School Motto', 'e.g. Excellence Through Education', defaultValue: 'Excellence Through Education'),
      _Field('description', 'Description', 'About your school', defaultValue: 'A leading institution providing quality education from primary through secondary level. We combine academic excellence with character development to prepare students for the future.'),
      _Field('students', 'Number of Students', '', defaultValue: '850'),
      _Field('teachers', 'Number of Teachers', '', defaultValue: '45'),
      _Field('years', 'Years Established', '', defaultValue: '15'),
      _Field('pass_rate', 'Pass Rate', '', defaultValue: '92%'),
      _Field('address', 'Address', '', defaultValue: 'Plot 23, Education Road, Kampala'),
      _Field('phone', 'Phone', '', defaultValue: '+256 700 123 456'),
      _Field('email', 'Email', '', defaultValue: 'info@brightfuture.ac.ug'),
    ],
  ),
];

// ── Screen ───────────────────────────────────────────────────────────────────

class SiteBuilderScreen extends ConsumerStatefulWidget {
  const SiteBuilderScreen({super.key});

  @override
  ConsumerState<SiteBuilderScreen> createState() => _SiteBuilderScreenState();
}

class _SiteBuilderScreenState extends ConsumerState<SiteBuilderScreen> {
  _TemplateInfo? _selected;
  final Map<String, TextEditingController> _controllers = {};
  WebViewController? _webViewController;
  bool _showPreview = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectTemplate(_TemplateInfo template) {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    for (final field in template.fields) {
      _controllers[field.key] = TextEditingController(text: field.defaultValue);
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);

    setState(() {
      _selected = template;
      _showPreview = false;
    });
  }

  Future<void> _buildSite() async {
    if (_selected == null) return;

    var html = await rootBundle.loadString('assets/templates/${_selected!.id}.html');

    for (final field in _selected!.fields) {
      final value = _controllers[field.key]?.text ?? field.defaultValue;
      html = html.replaceAll('{{${field.key}}}', value);
    }

    final encoded = base64Encode(utf8.encode(html));
    _webViewController?.loadRequest(Uri.parse('data:text/html;base64,$encoded'));

    setState(() => _showPreview = true);
  }

  void _back() {
    if (_showPreview) {
      setState(() => _showPreview = false);
    } else {
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.web, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(_selected == null ? 'Site Builder' : _showPreview ? 'Preview' : _selected!.name),
        ]),
        leading: _selected != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
        actions: const [StudioDrawerButton()],
      ),
      floatingActionButton: _selected != null && !_showPreview
          ? FloatingActionButton.extended(
              onPressed: _buildSite,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('BUILD'),
              backgroundColor: _selected!.color,
              foregroundColor: Colors.white,
            )
          : null,
      body: _selected == null
          ? _TemplatePicker(onSelect: _selectTemplate)
          : _showPreview
              ? _webViewController != null
                  ? WebViewWidget(controller: _webViewController!)
                  : const Center(child: CircularProgressIndicator())
              : _FieldEditor(template: _selected!, controllers: _controllers),
    );
  }
}

// ── Template picker ──────────────────────────────────────────────────────────

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({required this.onSelect});
  final void Function(_TemplateInfo) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose a Template', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 6),
          Text('Pick a design, fill in your info, and get a live website!', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          ..._templates.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              onTap: () => onSelect(t),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(t.icon, color: t.color, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text(t.description, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    )),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).hintColor),
                  ],
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ── Field editor ─────────────────────────────────────────────────────────────

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({required this.template, required this.controllers});
  final _TemplateInfo template;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: template.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: template.color.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.edit_note, color: template.color),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Fill in the details below, then tap BUILD to see your website!',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 20),
          ...template.fields.map((field) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: controllers[field.key],
              maxLines: field.key.contains('desc') || field.key == 'about' || field.key == 'description' ? 3 : 1,
              decoration: InputDecoration(
                labelText: field.label,
                hintText: field.hint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: template.color, width: 2),
                ),
              ),
            ),
          )),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
