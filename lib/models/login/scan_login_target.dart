enum ScanLoginType { web, pad }

class ScanLoginTarget {
  const ScanLoginTarget._(this.type, this.uri);

  final ScanLoginType type;
  final Uri uri;

  String get code =>
      uri.queryParameters[type == ScanLoginType.web
          ? 'qrcode_key'
          : 'auth_code'] ??
      '';

  String get needUpgrade => uri.queryParameters['need_upgrade'] ?? '0';

  Map<String, String> get parameters => switch (type) {
    ScanLoginType.web => {'qrcode_key': code},
    ScanLoginType.pad => {
      'auth_code': code,
      for (final key in ['mobi_app', 'login_session_id', 'spm_id'])
        key: ?uri.queryParameters[key],
    },
  };

  static ScanLoginTarget? fromUri(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    if (const {
          'account.bilibili.com',
          'app.bilibili.com',
          'passport.bilibili.com',
        }.contains(uri.host) &&
        const {
          '/h5/account-h5/auth/scan-web',
          '/qrcode/h5/login',
        }.contains(path)) {
      return ScanLoginTarget._(ScanLoginType.web, uri);
    }
    if (uri.host == 'passport.bilibili.com' &&
        const {
          '/x/passport-tv-login/h5/qrcode/auth',
          '/h5-app/passport/login/scan-pad',
        }.contains(path)) {
      return ScanLoginTarget._(ScanLoginType.pad, uri);
    }
    return null;
  }
}
