/// Whether this device has enough memory to run the offline AI.
///
/// The brain needs about 1.1 GB and the translator about 0.6–0.9 GB on top
/// of the app. Below the minimum, loading would be killed by the system
/// (Android) or swap until unusable (desktop), so the app stays in demo
/// answers and says why. The minimums are the targets' rated RAM less what
/// the system reserves: a 4 GB phone reports about 3.6 GB, an 8 GB PC about
/// 7.8 GB.
library;

export 'memory_support_stub.dart'
    if (dart.library.ffi) 'memory_support_native.dart';

/// Least total RAM, in GB, the AI is loaded with.
const kMinMemoryGbPhone = 3.0;
const kMinMemoryGbDesktop = 6.0;

/// Whether [totalGb] (null when it could not be read) is enough.
bool memoryIsEnough(double? totalGb, {required bool phone}) =>
    totalGb == null ||
    totalGb >= (phone ? kMinMemoryGbPhone : kMinMemoryGbDesktop);
