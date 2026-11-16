import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/scan.dart';
import 'package:PiliPlus/models/login/scan_login_target.dart';
import 'package:PiliPlus/pages/login/geetest/geetest_webview_dialog.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ScanLoginPage extends StatefulWidget {
  const ScanLoginPage({
    super.key,
    required this.target,
    required this.account,
  });

  final ScanLoginTarget target;
  final Account account;

  @override
  State<ScanLoginPage> createState() => _ScanLoginPageState();
}

class _ScanLoginPageState extends State<ScanLoginPage> {
  late final _http = ScanHttp(widget.account);
  LoadingState<Map<String, dynamic>> _scene = LoadingState.loading();
  final _codeController = TextEditingController();
  String? _envKey;
  String _verifyKey = '';
  String _verifiedCode = '';
  bool _transient = false;
  bool _submitting = false;
  bool _sendingSms = false;

  bool get _isPad => widget.target.type == ScanLoginType.pad;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scene = await _http.scene(widget.target);
    if (!mounted) return;
    setState(() => _scene = scene);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendSms() async {
    setState(() => _sendingSms = true);
    try {
      final pre = await _http.captcha();
      if (!mounted) return;
      if (pre case Success(:final response)) {
        final captcha = await GeetestWebviewDialog.geetest(
          response['gee_gt'],
          response['gee_challenge'],
        );
        if (captcha == null || !mounted) return;
        final sent = await _http.sendSms({
          'recaptcha_token': response['recaptcha_token'],
          'gee_challenge': captcha['geetest_challenge'],
          'gee_validate': captcha['geetest_validate'],
          'gee_seccode': captcha['geetest_seccode'],
        });
        if (!mounted) return;
        if (sent case Success(:final response)) {
          _verifyKey = response['captcha_key'];
          _verifiedCode = '';
          SmartDialog.showToast('短信已发送');
        } else {
          sent.toast();
        }
      } else {
        pre.toast();
      }
    } finally {
      if (mounted) setState(() => _sendingSms = false);
    }
  }

  Future<void> _confirm(Map<String, dynamic> scene) async {
    setState(() => _submitting = true);
    try {
      if (!_isPad &&
          scene['verify_tel'] == true &&
          (_verifiedCode.isEmpty ||
              _verifiedCode != _codeController.text.trim())) {
        if (_verifyKey.isEmpty || _codeController.text.trim().isEmpty) {
          SmartDialog.showToast('请获取并输入短信验证码');
          return;
        }
        final code = _codeController.text.trim();
        final checked = await _http.checkSms(_verifyKey, code);
        if (!mounted) return;
        if (!checked.isSuccess) {
          checked.toast();
          return;
        }
        _verifiedCode = code;
      }
      final res = await _http.confirm(
        target: widget.target,
        envKey: _envKey ?? '',
        transient: _transient || _envKey == 'PUBLIC_ENV',
        verifyKey: _verifyKey,
        verifyCode: _verifiedCode,
      );
      if (!mounted) return;
      if (res.isSuccess) {
        SmartDialog.showToast('登录成功');
        Get.back(result: true);
      } else if (res case Error(code: 86038)) {
        setState(() => _scene = res);
      } else {
        res.toast();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: switch (_scene) {
        Success(:final response) => _buildConfirmation(response),
        Error(:final errMsg, :final code) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errMsg ?? '请求失败'),
              TextButton(
                onPressed: code == 86038
                    ? Get.back
                    : () {
                        setState(() => _scene = LoadingState.loading());
                        _load();
                      },
                child: Text(code == 86038 ? '重新扫描' : '重试'),
              ),
            ],
          ),
        ),
        _ => m3eLoading,
      },
    );
  }

  Widget _buildConfirmation(Map<String, dynamic> scene) {
    final List environments = !_isPad && scene['obtain_env'] == true
        ? scene['env_show_list']
        : const [];
    final Map? app = scene['app'];
    final needUpgrade = _isPad ? widget.target.needUpgrade : '0';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _isPad
                  ? '登录哔哩哔哩 HD / Pad 客户端'
                  : app == null
                  ? '登录哔哩哔哩网页版'
                  : '登录${app['title']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text('授权账号：${widget.account.mid}'),
            if (_isPad) ...[
              const SizedBox(height: 16),
              const Text('请确认正在登录的设备在您身边，并且是您本人操作。'),
            ],
            if (needUpgrade == '1' || needUpgrade == '2') ...[
              const SizedBox(height: 16),
              Text(
                needUpgrade == '2'
                    ? '目标设备的哔哩哔哩版本过低，请更新客户端后重新扫码登录。'
                    : '目标设备的哔哩哔哩版本过低，部分功能可能无法正常使用，建议更新客户端。',
              ),
            ],
            if (scene['location_diff'] == true) ...[
              const SizedBox(height: 16),
              Text('异地登录：${scene['qrcode_location']}'),
              if (_isPad)
                Text(
                  '请核实登录设备和地点，授权他人登录可能导致账号被盗。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
            if (environments.isNotEmpty) ...[
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: _envKey,
                onChanged: _submitting
                    ? (_) {}
                    : (value) => setState(() => _envKey = value),
                child: Column(
                  children: environments
                      .map(
                        (env) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: env['env_key'],
                          title: Text(env['env_desc']),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (scene['transient'] == true || _envKey == 'PUBLIC_ENV')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('短期登录（24 小时）'),
                value: _envKey == 'PUBLIC_ENV' || _transient,
                onChanged: _submitting || _envKey == 'PUBLIC_ENV'
                    ? null
                    : (value) => setState(() => _transient = value!),
              ),
            if (!_isPad && scene['verify_tel'] == true) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '短信验证码',
                  border: const OutlineInputBorder(),
                  suffixIcon: TextButton(
                    onPressed: _sendingSms || _submitting ? null : _sendSms,
                    child: Text(_sendingSms ? '发送中' : '获取验证码'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _submitting ||
                      _sendingSms ||
                      needUpgrade == '2' ||
                      (environments.isNotEmpty && _envKey == null)
                  ? null
                  : () => _confirm(scene),
              child: Text(
                _submitting
                    ? '登录中'
                    : needUpgrade == '1'
                    ? '继续登录'
                    : '确认登录',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting ? null : Get.back,
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
