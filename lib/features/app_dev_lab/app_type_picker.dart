import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';
import 'app_type_catalog.dart';

/// The "pick from a list" fallback for learners who'd rather choose a type
/// than describe one — a real picker, not the old chat-typed numbered list.
Future<AppTypeEntry?> showAppTypePicker(BuildContext context) {
  return showModalBottomSheet<AppTypeEntry>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _AppTypeListSheet(),
  );
}

class _AppTypeListSheet extends StatefulWidget {
  @override
  State<_AppTypeListSheet> createState() => _AppTypeListSheetState();
}

class _AppTypeListSheetState extends State<_AppTypeListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final entries = query.isEmpty
        ? kAppTypes
        : kAppTypes.where((e) => e.name.toLowerCase().contains(query)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                tr(context, 'Choose an app type'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: tr(context, 'Search app types…'),
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
                          title: Text(entry.name),
                          subtitle: Text(
                            entry.featureOptions.take(3).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
