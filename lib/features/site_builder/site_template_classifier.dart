import '../create/keyword_classifier.dart';
import 'site_template_catalog.dart';

/// Best-fit website template for a free-text description. Never null — an
/// unmatched description gets [kGenericSiteTemplate].
SiteTemplateEntry classifySiteTemplate(String text) => classifyByKeywords(
  text,
  kSiteTemplates,
  (e) => e.keywords,
  kGenericSiteTemplate,
);
