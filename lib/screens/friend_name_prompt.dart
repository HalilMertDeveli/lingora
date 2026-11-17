import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/friends.dart';
import '../services/profile.dart';

/// True while friends would see only the generic name ("Dilmaç öğrencisi").
bool needsFriendName(WidgetRef ref) =>
    isDefaultFriendName(ref.read(friendsApiProvider)?.myName ?? ref.read(myDisplayNameProvider));

/// Before a code, an add or a request: when the user has no name yet, asks
/// "Arkadaşların seni hangi adla görsün?" and saves it as the Profil name.
/// Returns false when they cancel (nothing is sent then).
Future<bool> ensureFriendName(BuildContext context, WidgetRef ref) async {
  if (!needsFriendName(ref)) return true;
  final name = await showDialog<String>(context: context, builder: (_) => const FriendNameDialog());
  if (name == null) return false;
  await ref.read(profileProvider.notifier).setName(name);
  return !needsFriendName(ref);
}

class FriendNameDialog extends StatefulWidget {
  const FriendNameDialog({super.key});

  @override
  State<FriendNameDialog> createState() => _FriendNameDialogState();
}

class _FriendNameDialogState extends State<FriendNameDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final name = cleanDisplayName(_c.text);
    if (name == null || isDefaultFriendName(name)) {
      setState(() => _error = 'Bir ad yaz (en fazla $maxNameLength harf).');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('friend-name-dialog'),
    title: const Text('Arkadaşların seni hangi adla görsün?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bu ad Profil\'deki adın olur; istediğin zaman değiştirebilirsin.'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('friend-name-field'),
          controller: _c,
          autofocus: true,
          maxLength: maxNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Adın', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      TextButton(key: const ValueKey('friend-name-save'), onPressed: _save, child: const Text('Kaydet')),
    ],
  );
}
