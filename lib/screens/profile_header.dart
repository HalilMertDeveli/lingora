import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/gold_wallet.dart';
import '../data/shop_catalog.dart';
import '../services/firebase/firebase_providers.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../ui/my_avatar.dart';
import 'onboarding_screen.dart' show LingoraLogo;

/// Opens the gallery or the camera and returns the chosen image's bytes;
/// null when the learner cancelled. Overridden in tests.
typedef AvatarPicker = Future<Uint8List?> Function(ImageSource source);

final avatarPickerProvider = Provider<AvatarPicker>(
  (ref) => (source) async {
    // A first shrink on the platform side keeps the decode below cheap.
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.front,
    );
    return file?.readAsBytes();
  },
);

/// Turns the picked bytes into the stored JPEG. Overridden in tests, which
/// run [processAvatar] directly.
final avatarProcessorProvider = Provider<Future<Uint8List> Function(Uint8List)>((ref) => processAvatarAsync);

/// Top of the Profil tab: the learner's photo (tap to change) and name.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  static const size = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final wallet = ref.watch(walletProvider);
    final account = ref.watch(authStateProvider).value?.displayName?.trim().split(RegExp(r'\s+')).first;
    final name = profile.name ?? cleanDisplayName(account) ?? 'Öğrenci';
    // Çocuk modu: Pofuduk's square face is the avatar and photos are off.
    final kid = Brand.isKid;
    final avatarItem = equippedIn(wallet, WalletSlot.avatar);
    final Widget avatar = kid
        ? const MyAvatar(size: size, kidKey: Key('kid-avatar'))
        : Semantics(
            button: true,
            label: 'Profil fotoğrafını değiştir',
            child: InkWell(
              key: const ValueKey('profile-avatar'),
              customBorder: const CircleBorder(),
              onTap: () => _photoSheet(context, ref),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Photo or Mağaza avatar (the choice below), in the frame.
                  const MyAvatar(
                    size: size,
                    fallback: LingoraLogo(size: size),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Brand.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Brand.surface, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );

    return Row(
      children: [
        avatar,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                key: const ValueKey('profile-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text('İngilizce öğreniyor', style: TextStyle(color: Brand.muted)),
              if (!kid && avatarItem != null) ...[
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  key: const ValueKey('profile-face'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(
                      value: false,
                      enabled: profile.photo != null,
                      icon: const Icon(Icons.photo_camera_rounded, size: 16),
                      label: const Text('Fotoğraf'),
                    ),
                    ButtonSegment(value: true, label: Text('${avatarItem.emoji} Avatar')),
                  ],
                  selected: {prefersAvatar(wallet) || profile.photo == null},
                  onSelectionChanged: (s) => ref.read(goldWalletProvider).useAvatarFace(s.first),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('profile-edit-name'),
          tooltip: 'Adını düzenle',
          icon: Icon(Icons.edit_rounded, color: Brand.muted),
          onPressed: () => _editName(context, ref),
        ),
      ],
    );
  }

  Future<void> _photoSheet(BuildContext context, WidgetRef ref) async {
    final hasPhoto = ref.read(profileProvider).photo != null;
    final account = ref.read(accountUidProvider) != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('avatar-gallery'),
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            ListTile(
              key: const ValueKey('avatar-camera'),
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Fotoğraf çek'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                key: const ValueKey('avatar-remove'),
                leading: Icon(Icons.delete_outline_rounded, color: Brand.error),
                title: Text('Fotoğrafı kaldır', style: TextStyle(color: Brand.error)),
                onTap: () => Navigator.pop(c, 'remove'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                account
                    ? 'Fotoğrafın hesabına kaydedilir; arkadaşların ve diğer telefonların görür.'
                    : 'Misafir olarak fotoğrafın yalnızca bu cihazda kalır.',
                style: TextStyle(color: Brand.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final notifier = ref.read(profileProvider.notifier);
    if (choice == 'remove') {
      await notifier.removePhoto();
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final raw = await ref.read(avatarPickerProvider)(
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (raw == null) return;
      final jpeg = await ref.read(avatarProcessorProvider)(raw);
      await notifier.setPhoto(jpeg);
      // A new photo is meant to be seen: show it instead of the avatar.
      ref.read(goldWalletProvider).useAvatarFace(false);
    } on AvatarException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // E.g. camera permission refused.
      messenger?.showSnackBar(
        const SnackBar(content: Text('Fotoğraf alınamadı. Kamera ya da galeri iznini kontrol et.')),
      );
    }
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final current = ref.read(profileProvider).name ?? '';
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Görünen ad'),
        content: TextField(
          key: const ValueKey('profile-name-field'),
          controller: controller,
          autofocus: true,
          maxLength: maxNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Adın',
            helperText: 'Arkadaşların ve ligde böyle görünür',
          ),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            key: const ValueKey('profile-name-save'),
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) await ref.read(profileProvider.notifier).setName(result);
  }
}
