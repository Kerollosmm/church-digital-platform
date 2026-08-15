import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/repositories/videos_repository.dart';
import 'package:mobile/services/app_routes.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class VideoPurchaseScreen extends StatefulWidget {
  const VideoPurchaseScreen({
    super.key,
    required this.repository,
    this.gateway,
    this.isLoggedIn,
  });

  final VideosRepository repository;
  final AuthGateway? gateway;
  final bool Function()? isLoggedIn;

  @override
  State<VideoPurchaseScreen> createState() => _VideoPurchaseScreenState();
}

class _VideoPurchaseScreenState extends State<VideoPurchaseScreen> {
  late Future<List<Map<String, dynamic>>> _videos;

  @override
  void initState() {
    super.initState();
    _videos = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      widget.repository.fetchVideos();

  Future<void> _buy(int videoId) async {
    await PhoneVerifyGate.ensureAuth(
      context,
      gateway: resolveAuthGateway(widget.gateway),
      isLoggedIn: widget.isLoggedIn,
      onVerified: () async {
        await runGuarded(
          () async {
            final payment = await widget.repository.purchaseVideo(videoId);
            if (!mounted) return;
            context.pushNamed(
              AppRoutes.paymentRedirect,
              extra: {'video': true, 'payment_id': payment?['id']},
            );
          },
          onError: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        );
      },
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    final str = raw.toString();
    if (str.isEmpty) return '';
    return str.length >= 10 ? str.substring(0, 10) : str;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          AppStrings.videosStoreTitle,
          style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _videos,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return Center(
              child: Text(
                AppStrings.videosEmpty,
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            );
          }

          final featured = rows.first;
          final remaining = rows.skip(1).toList();
          final formattedDate = _formatDate(featured['event_date']);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Featured player card (top)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            color: AppColors.primaryContainer,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle,
                                size: 64.0,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                featured['title_ar']?.toString() ?? '',
                                style: AppTypography.headlineMd.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                              if (formattedDate.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  formattedDate,
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // 2. Section header «مكتبة الفيديوهات»
                Text(
                  AppStrings.videosLibraryTitle,
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // 3. Video grid (remaining rows)
                if (remaining.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpacing.sm,
                          crossAxisSpacing: AppSpacing.sm,
                          childAspectRatio: 0.72,
                        ),
                    itemCount: remaining.length,
                    itemBuilder: (context, index) {
                      final v = remaining[index];
                      final isPurchased = v['privacy'] == 'UNLISTED';
                      final priceStr = '${v['price']} ${AppStrings.egp}';

                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.glassBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 20,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  color: AppColors.surfaceVariant,
                                  width: double.infinity,
                                  child: const Center(
                                    child: Icon(
                                      Icons.movie,
                                      size: 40.0,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v['title_ar']?.toString() ?? '',
                                      style: AppTypography.labelMd.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    if (isPurchased)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            AppStrings.purchasedLabel,
                                            style: AppTypography.labelMd
                                                .copyWith(
                                                  color: AppColors.secondary,
                                                ),
                                          ),
                                          const Icon(
                                            Icons.play_arrow,
                                            color: AppColors.primary,
                                          ),
                                        ],
                                      )
                                    else
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            priceStr,
                                            style: AppTypography.labelMd
                                                .copyWith(
                                                  color: AppColors
                                                      .primaryContainer,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.secondary,
                                              foregroundColor:
                                                  AppColors.onSecondary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12.0,
                                                  ),
                                              minimumSize: const Size(48, 36),
                                            ),
                                            onPressed: () =>
                                                _buy(v['id'] as int),
                                            child: const Text(
                                              AppStrings.buyVideo,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
