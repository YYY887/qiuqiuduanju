import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = colors.primary;
    final bar = GlassTabBar.bottom(
      tabs: [
        for (final (index, destination) in destinations.indexed)
          GlassTab(
            icon: KeyedSubtree(
              key: ValueKey('bottom-nav-$index'),
              child: destination.icon,
            ),
            activeIcon: destination.selectedIcon ?? destination.icon,
            label: destination.label,
            semanticLabel: destination.label,
          ),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onDestinationSelected,
      horizontalPadding: 18,
      verticalPadding: 4,
      barHeight: 66,
      indicatorColor: dark ? const Color(0xCC695251) : const Color(0xD9F5C5B6),
      selectedIconColor: accent,
      selectedLabelColor: accent,
      unselectedIconColor: colors.onSurfaceVariant,
      unselectedLabelColor: colors.onSurfaceVariant,
      settings: LiquidGlassSettings(
        bodyMode: GlassBodyMode.clear,
        glassColor: dark ? const Color(0xB5323239) : const Color(0xCCFFF9F3),
        backerColor: dark ? const Color(0x66201F24) : const Color(0x66FFF9F3),
        thickness: 30,
        blur: 4,
        lightIntensity: .6,
        ambientStrength: 1,
        refractiveIndex: 1.59,
        saturation: .7,
      ),
      quality: GlassQuality.standard,
      backgroundQuality: GlassQuality.standard,
      glowOpacity: dark ? 0 : .35,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.orientationOf(context) == Orientation.landscape
              ? 480
              : 520,
        ),
        child: bar,
      ),
    );
  }
}
