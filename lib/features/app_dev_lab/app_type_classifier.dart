import '../create/keyword_classifier.dart';
import 'app_type_catalog.dart';

/// Best-fit app type for a free-text description. Never null: the build's
/// backend and fallback template are keyed off the result, so an unmatched
/// description gets [kGenericAppType] rather than no type at all.
AppTypeEntry classifyAppType(String text) =>
    classifyByKeywords(text, kAppTypes, (e) => e.keywords, kGenericAppType);
