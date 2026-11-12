import 'package:flutter/material.dart';

import '../theme.dart';

/// The white circular back button the mockups draw top-left (sign in, sign up, search results).
/// It is an `InkWell` on a circular `Material` with a soft shadow.
class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key, this.onPressed});

  /// Defaults to popping the current route.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // Lighter than the card shadow: the AppBar's leading slot would clip a wide blur.
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Tooltip(
              message: 'Back',
              child: Icon(Icons.arrow_back, size: 22, color: carShareText),
            ),
          ),
        ),
      ),
    ),
  );
}

/// An AppBar that holds the [RoundBackButton] and, optionally, one [trailing] widget on the
/// right (the sign-up chip), as on the mockups' auth screens. With a [title] it is the header of
/// the list and form screens ("My vehicles", "Add a vehicle"); [actions] go before [trailing].
AppBar roundBackAppBar(
  BuildContext context, {
  VoidCallback? onBack,
  Widget? trailing,
  String? title,
  List<Widget> actions = const [],
}) => AppBar(
  automaticallyImplyLeading: false,
  leadingWidth: 76,
  toolbarHeight: 68,
  titleSpacing: 14,
  title: title == null ? null : Text(title),
  leading: Padding(
    padding: const EdgeInsets.only(left: 24),
    child: RoundBackButton(onPressed: onBack),
  ),
  actions: [
    ...actions,
    if (trailing != null)
      Padding(padding: const EdgeInsets.only(right: 24), child: trailing),
  ],
);
