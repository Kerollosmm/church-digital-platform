import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/booking/my_bookings_screen.dart';
import '../features/booking/services_list_screen.dart';
import '../features/complaints/complaints_repository.dart';
import '../features/complaints/complaints_screen.dart';
import '../features/portal/portal_repository.dart';
import '../features/portal/priests_directory_sheet.dart';
import '../repositories/booking_repository.dart';
import '../screens/home_hub_screen.dart';
import '../services/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../features/family_archive/sacramental_repository.dart';
import 'top_bar.dart';

class BottomNavScaffold extends StatefulWidget {
  const BottomNavScaffold({
    super.key,
    this.homeTab,
    required this.bookingRepository,
    this.complaintsRepository,
    this.portalRepository,
    this.sacramentalRepository,
    this.complaintsTab,
    this.myBookingsTab,
    this.initialIndex = 0,
  });

  final Widget? homeTab;
  final BookingRepository bookingRepository;
  final ComplaintsRepository? complaintsRepository;
  final PortalRepository? portalRepository;
  final SacramentalRecordsRepository? sacramentalRepository;
  final Widget? complaintsTab;
  final Widget? myBookingsTab;
  final int initialIndex;

  @override
  State<BottomNavScaffold> createState() => _BottomNavScaffoldState();
}

class _BottomNavScaffoldState extends State<BottomNavScaffold> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  void _switchTab(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _buildHomeTab() {
    if (widget.homeTab != null) return widget.homeTab!;
    final portalRepo = widget.portalRepository ?? EmptyPortalRepository();
    return HomeHubScreen(
      repository: portalRepo,
      onTapMass: () => _switchTab(1),
      onTapConfession: () => PriestsDirectorySheet.show(context, portalRepo),
      onTapBooking: () => _switchTab(1),
      onTapEventBooking: () => context.push('/event-booking'),
      onTapComplaints: () => _switchTab(2),
    );
  }

  Widget _buildComplaintsTab() {
    if (widget.complaintsTab != null) return widget.complaintsTab!;
    return ComplaintsScreen(
      repository: widget.complaintsRepository ?? EmptyComplaintsRepository(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          ServicesListScreen(repository: widget.bookingRepository),
          _buildComplaintsTab(),
          widget.myBookingsTab ??
              MyBookingsScreen(repository: widget.bookingRepository),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              border: Border(
                top: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.1),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  label: AppStrings.tabHome,
                  activeIcon: Icons.home,
                  inactiveIcon: Icons.home_outlined,
                ),
                _buildNavItem(
                  index: 1,
                  label: AppStrings.tabBooking,
                  activeIcon: Icons.event_available,
                  inactiveIcon: Icons.event_available_outlined,
                ),
                _buildNavItem(
                  index: 2,
                  label: AppStrings.tabComplaints,
                  activeIcon: Icons.edit_note,
                  inactiveIcon: Icons.edit_note_outlined,
                ),
                _buildNavItem(
                  index: 3,
                  label: AppStrings.tabProfile,
                  activeIcon: Icons.person,
                  inactiveIcon: Icons.person_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData activeIcon,
    required IconData inactiveIcon,
  }) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: isActive
            ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0)
            : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isActive ? AppColors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              color: isActive
                  ? AppColors.onSecondaryContainer
                  : AppColors.onSurfaceVariant,
              size: 24.0,
            ),
            const SizedBox(height: 2.0),
            Text(
              label,
              style: AppTypography.labelMd.copyWith(
                color: isActive
                    ? AppColors.onSecondaryContainer
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
