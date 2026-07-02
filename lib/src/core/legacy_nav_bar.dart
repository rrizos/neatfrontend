import 'package:flutter/material.dart';

import 'post_card.dart' show decodeAvatarUrl;

/// The Flutter-rendered bottom nav bar used on Android and pre-iOS26 devices
/// (iOS 26 uses a native UITabBar overlay instead — see HomePage's
/// `_kTabChannel`). Extracted so it can be reused both as HomePage's own
/// `bottomNavigationBar` and on pages pushed on top of it (e.g. another
/// user's profile), so the bar stays visible instead of disappearing behind
/// the pushed route.
class LegacyNavBar extends StatelessWidget {
  const LegacyNavBar({
    super.key,
    required this.isLight,
    required this.currentIndex,
    required this.onTap,
    required this.avatarUrl,
  });

  final bool isLight;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    final avatarBytes = decodeAvatarUrl(avatarUrl);
    final activeColor = isLight ? Colors.black : Colors.white;
    final imageProvider = avatarBytes != null ? MemoryImage(avatarBytes) : null;

    Widget profileIcon({required bool active}) {
      if (!active) {
        return CircleAvatar(
          radius: 13,
          backgroundColor: isLight
              ? const Color(0xffe6e9ef)
              : const Color(0xff2a2a2a),
          foregroundImage: imageProvider,
          child: imageProvider == null
              ? Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: isLight
                      ? const Color(0xff6d6d6d)
                      : const Color(0xff8c8c8c),
                )
              : null,
        );
      }
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: activeColor, width: 2),
        ),
        alignment: Alignment.center,
        child: CircleAvatar(
          radius: 12,
          backgroundColor: isLight
              ? const Color(0xffe6e9ef)
              : const Color(0xff2a2a2a),
          foregroundImage: imageProvider,
          child: imageProvider == null
              ? Icon(Icons.person_rounded, size: 13, color: activeColor)
              : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          selectedItemColor: activeColor,
          unselectedItemColor: isLight
              ? const Color(0xff6d6d6d)
              : const Color(0xff8c8c8c),
          elevation: 0,
          backgroundColor: isLight ? Colors.white : const Color(0xff151515),
          iconSize: 26,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          onTap: onTap,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline_rounded),
              activeIcon: Icon(Icons.add_circle_rounded),
              label: 'Create',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: profileIcon(active: false),
              activeIcon: profileIcon(active: true),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
