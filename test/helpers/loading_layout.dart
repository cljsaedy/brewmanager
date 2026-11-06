import 'dart:async';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/layout/app_layout.dart';

// a count store that never finishes opening, for tests that only look at the frame around the tabs
Future<CountStore> _neverOpens() => Completer<CountStore>().future;

// the app layout stuck on loading, so the test never touches the real database
const AppLayout loadingLayout = AppLayout(openCountStore: _neverOpens);
