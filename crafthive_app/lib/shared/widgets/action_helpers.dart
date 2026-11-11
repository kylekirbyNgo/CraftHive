import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import 'common.dart';
import 'craft_icon.dart';

const _maxPhotoBytes = 5 * 1024 * 1024;

/// Picks one photo from the gallery (a receipt screenshot or a reference photo).
/// The picker shrinks it first; files over 5 MB are refused like listing photos.
Future<PickedImage?> pickOnePhoto(BuildContext context) async {
  try {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      if (context.mounted) showMessage(context, 'That photo is over 5 MB. Choose a smaller one.');
      return null;
    }
    return PickedImage(bytes: bytes, fileName: f.name);
  } catch (e) {
    debugPrint('CraftHive: photo picker failed: $e');
    if (context.mounted) showMessage(context, "We couldn't open your photos. Allow CraftHive to use your photos, then try again.");
    return null;
  }
}

/// Runs a save and shows the error message if it fails. Returns true when it worked.
Future<bool> runWithMessage(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } on AppFailure catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Yes/no question before something that cannot be undone.
Future<bool> confirmAction(BuildContext context, {required String title, required String message, required String confirmLabel, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppText.screenTitle),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: danger ? AppColors.brick : AppColors.moss, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Bottom sheet with one text box (decline reason, changes to ask for…).
/// Returns the trimmed text, or null when closed.
Future<String?> askForText(BuildContext context, {required String title, required String hint, required String button, String? subtitle, int minLength = 3}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TextSheet(title: title, hint: hint, button: button, subtitle: subtitle, minLength: minLength),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.title, required this.hint, required this.button, required this.minLength, this.subtitle});
  final String title;
  final String hint;
  final String button;
  final String? subtitle;
  final int minLength;
  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.title, style: AppText.screenTitle),
              if (widget.subtitle != null) ...[const SizedBox(height: 4), Text(widget.subtitle!, style: AppText.caption.copyWith(fontSize: 13))],
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(hintText: widget.hint, errorText: _error),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: widget.button,
                onPressed: () {
                  final t = _ctrl.text.trim();
                  if (t.length < widget.minLength) {
                    setState(() => _error = 'Write at least ${widget.minLength} characters.');
                    return;
                  }
                  Navigator.pop(context, t);
                },
              ),
            ]),
          ),
        ),
      );
}

/// A photo from the private bucket (payment proof, reference photo), opened
/// with a signed link only the order's buyer and seller can get.
class PrivateImage extends ConsumerWidget {
  const PrivateImage({super.key, required this.path, this.height = 160});
  final String path;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(privateImageUrlProvider(path));
    Widget box(Widget child) => Container(
          height: height,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.linen)),
          child: child,
        );
    return url.when(
      loading: () => box(const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))),
      error: (_, __) => box(const Center(child: CraftIcon(CraftIcons.image, size: 28, color: AppColors.grayBrown))),
      data: (u) => u.isEmpty
          ? box(const Center(child: CraftIcon(CraftIcons.image, size: 28, color: AppColors.grayBrown)))
          : box(InkWell(
              onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(u)))),
              child: Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: CraftIcon(CraftIcons.image, size: 28, color: AppColors.grayBrown))),
            )),
    );
  }
}
