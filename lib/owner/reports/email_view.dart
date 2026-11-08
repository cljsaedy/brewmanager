import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';

// shows an email's html inside the app, the same as the owner's mail app shows it
// a webview = a small browser inside the app, flutter widgets cant draw html tables and inline styles themselves
// it only shows the html given here: javascript off, and tapping a link opens nothing (the emails have none)
class EmailView extends StatefulWidget {
  const EmailView({super.key, required this.html});

  final String html;

  @override
  State<EmailView> createState() => _EmailViewState();
}

class _EmailViewState extends State<EmailView> {
  late final WebViewController _controller = WebViewController()
    // the emails have no scripts, off is safer
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setBackgroundColor(AppColors.cream)
    // only the html loaded here, never a web page from a link
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => request.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EmailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // another email was picked
    if (oldWidget.html != widget.html) _load();
  }

  // the email body is only a part of a page, this wraps it in a full one
  // viewport = fit the page to the panel's width like a phone does
  void _load() {
    _controller.loadHtmlString(
      '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '</head><body style="margin:0">${widget.html}</body></html>',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
