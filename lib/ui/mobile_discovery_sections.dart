import 'package:flutter/material.dart';

import '../core/core_bridge.dart';
import '../core/models.dart';
import 'widgets.dart';

class TrendingDramaRow extends StatelessWidget {
  const TrendingDramaRow({
    super.key,
    required this.dramas,
    required this.repository,
    required this.onOpen,
  });

  final List<Drama> dramas;
  final AppRepository repository;
  final ValueChanged<Drama> onOpen;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final tileWidth = wide ? 226.0 : 166.0;
    return SizedBox(
      height: wide ? 193 : 155,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dramas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final drama = dramas[index];
          return SizedBox(
            width: tileWidth,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onOpen(drama),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: wide ? 152 : 112,
                    child: DramaCover(
                      drama: drama,
                      repository: repository,
                      radius: 13,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    drama.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
