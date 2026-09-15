import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_update_service.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final _service = AppUpdateService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      final update = await _service.checkOnce();
      if (!mounted || update == null) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(service: _service, update: update),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível verificar atualizações. Tente na próxima abertura.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.update});
  final AppUpdateService service;
  final AppUpdate update;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _message;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _message = null;
      _progress = null;
    });
    try {
      await widget.service.downloadAndInstall(
        widget.update,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(
        () => _message = 'Confirme a instalação no Android. Se cancelar, toque em Atualizar para tentar novamente.',
      );
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.code == 'permission_required'
              ? 'Autorize a instalação desta fonte nas configurações e toque em Atualizar novamente.'
              : 'Instalador indisponível: ${error.message ?? error.code}',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Não foi possível baixar ou instalar a atualização. Verifique a conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.update.mandatory && !_busy,
    child: AlertDialog(
      title: const Text('Atualização disponível'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A versão ${widget.update.version} está disponível.'),
          if (widget.update.mandatory)
            const Text('Esta atualização é obrigatória para continuar.'),
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            Text(
              _progress == null
                  ? 'Preparando atualização…'
                  : 'Baixando: ${(_progress! * 100).round()}%',
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
        ],
      ),
      actions: [
        if (!widget.update.mandatory)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Agora não'),
          ),
        TextButton(
          onPressed: _busy ? null : _install,
          child: const Text('Atualizar'),
        ),
      ],
    ),
  );
}
