/// Content that the preview pipeline used to inject on its own.
///
/// The old repair path replaced any document it judged "not interactive
/// enough" with a canned demo shell — tabs, a notes list, a theme toggle, a
/// checkout calculator and a quiz — so students saw a site nobody wrote.
/// Every preview assertion checks this list stays absent: the pane may only
/// ever render the code that was handed to it.
const kInventedPreviewContent = <String>[
  'OTIC_INTERACTIVE_RUNTIME',
  'Interactive offline preview',
  'Checkout calculator',
  'Quick quiz',
  'Theme lab',
  'Toggle accent',
  'Live total',
  'Confirm order',
  'Save note',
  'Capital of Kenya',
];
