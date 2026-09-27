import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';
import 'site_template_catalog.dart';

/// The "pick from a list" fallback for learners who'd rather choose a site
/// type than describe one.
Future<SiteTemplateEntry?> showSiteTemplatePicker(BuildContext context) {
  return showModalBottomSheet<SiteTemplateEntry>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SiteTemplateListSheet(),
  );
}

class _SiteTemplateListSheet extends StatefulWidget {
  @override
  State<_SiteTemplateListSheet> createState() => _SiteTemplateListSheetState();
}

class _SiteTemplateListSheetState extends State<_SiteTemplateListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final entries = query.isEmpty
        ? kSiteTemplates
        : kSiteTemplates
              .where((e) => e.name.toLowerCase().contains(query))
              .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                tr(context, 'Choose a website type'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: tr(context, 'Search website types…'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(tr(context, 'No matches.')))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final entry = entries[i];
                        return ListTile(
                          leading: Icon(entry.icon),
                          title: Text(entry.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
