import 'dart:html' as html;

void removeAppLoadingSplash() {
  // ignore: undefined_prefixed_name
  final loader = html.document.getElementById('app-loading');
  loader?.remove();
}