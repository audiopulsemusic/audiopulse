import 'package:flutter/material.dart';

/// Dark themed skeleton box for placeholder loading states
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: const Color(0x14FFFFFF),
        ),
      ),
    );
  }
}

/// Skeletons for search results, artist candidates, and discographies
class SearchSkeletons {
  static Widget buildSkeletonSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Squelette de l'en-tête de l'artiste
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: const [
              SkeletonBox(width: 36, height: 36, borderRadius: 18),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 120, height: 15, borderRadius: 4),
                  SizedBox(height: 4),
                  SkeletonBox(width: 60, height: 10, borderRadius: 4),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Squelette des sorties / albums
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: const [
              SkeletonBox(width: 12, height: 12, borderRadius: 6),
              SizedBox(width: 6),
              SkeletonBox(width: 130, height: 10, borderRadius: 4),
            ],
          ),
        ),
        SizedBox(
          height: 145,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 100, height: 100, borderRadius: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 12, borderRadius: 4),
                SizedBox(height: 4),
                SkeletonBox(width: 60, height: 9, borderRadius: 4),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Squelette des 3 morceaux YouTube
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x800E121B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              children: const [
                SkeletonBox(width: 44, height: 44, borderRadius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 180, height: 14, borderRadius: 4),
                      SizedBox(height: 6),
                      SkeletonBox(width: 100, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                SkeletonBox(width: 28, height: 12, borderRadius: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
