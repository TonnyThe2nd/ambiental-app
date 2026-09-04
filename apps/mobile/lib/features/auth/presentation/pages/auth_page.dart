import 'package:flutter/material.dart';

import '../../application/auth_service.dart';
import '../../../../core/device/location_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.auth,
    required this.locationService,
  });
  final AuthService auth;
  final LocationService locationService;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool register = false;
  bool loading = false;
  bool obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      if (register) {
        final place = await widget.locationService.current();
        await widget.auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          latitude: place.latitude,
          longitude: place.longitude,
        );
      } else {
        await widget.auth.login(email: _email.text, password: _password.text);
        try {
          final place = await widget.locationService.current();
          await widget.auth.updateLocation(
            latitude: place.latitude,
            longitude: place.longitude,
          );
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0xFFD9EEE8),
                      child: Icon(
                        Icons.eco_rounded,
                        size: 35,
                        color: Color(0xFF176B5B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    register ? 'Crie sua conta' : 'Bem-vindo de volta',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF18332D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    register
                        ? 'Participe do cuidado com a sua cidade.'
                        : 'Entre para acompanhar e registrar ocorrências.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF667C75)),
                  ),
                  const SizedBox(height: 30),
                  if (register) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Informe seu nome.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) => v != null && v.contains('@')
                        ? null
                        : 'Informe um e-mail válido.',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: obscure,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => (v?.length ?? 0) < (register ? 8 : 1)
                        ? 'A senha deve ter ao menos 8 caracteres.'
                        : null,
                  ),
                  if (register) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirme a senha',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      validator: (v) => v == _password.text
                          ? null
                          : 'As senhas não coincidem.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: loading ? null : _submit,
                    icon: loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(register ? Icons.person_add_alt_1 : Icons.login),
                    label: Text(register ? 'Criar conta' : 'Entrar'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => register = !register),
                    child: Text(
                      register
                          ? 'Já tem uma conta? Entrar'
                          : 'Ainda não tem conta? Cadastre-se',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
