import 'package:flutter/material.dart';
import '../../core/auth/auth_gateway.dart';
import '../../core/auth/phone_verify_gate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import 'complaints_models.dart';
import 'complaints_repository.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({
    super.key,
    required this.repository,
    this.gateway,
    this.isLoggedIn,
  });

  final ComplaintsRepository repository;
  final AuthGateway? gateway;
  final bool Function()? isLoggedIn;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _selectedCategory = 'عامة';
  bool _isSubmitting = false;
  late Future<List<ComplaintItem>> _complaintsFuture;

  static const List<String> _categories = [
    'عامة',
    'خدمات الكنيسة',
    'اقتراحات',
    'رعوية',
    'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _loadComplaints() {
    setState(() {
      _complaintsFuture = widget.repository.myComplaints();
    });
  }

  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final text = _descriptionController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.repository.submitComplaint(
        category: _selectedCategory,
        body: text,
      );
      if (!mounted) return;
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال الشكوى/الاقتراح بنجاح وحفظها بسرية'),
        ),
      );
      _loadComplaints();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر إرسال الشكوى: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = widget.gateway ?? resolveAuthGateway(null);

    return PhoneVerifyGate(
      gateway: gateway,
      isLoggedIn: widget.isLoggedIn,
      onVerified: _loadComplaints,
      child: Scaffold(
        appBar: AppBar(title: const Text('الشكاوى والمقترحات')),
        body: RefreshIndicator(
          onRefresh: () async => _loadComplaints(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Form Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تقديم شكوى أو اقتراح جديد',
                          style: AppTypography.headlineMd.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'يتم تشفير الشكوى وحمايتها ولا يطلع عليها سوى الآباء الكهنة أو إدارة الكنيسة.',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: InputDecoration(
                            labelText: 'التصنيف',
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          items: _categories
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedCategory = val);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          maxLength: 4000,
                          decoration: InputDecoration(
                            labelText: 'تفاصيل الشكوى أو الاقتراح',
                            hintText: 'اكتب رسالتك هنا بكل وضوح...',
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          validator: (val) {
                            final trimmed = (val ?? '').trim();
                            if (trimmed.isEmpty)
                              return 'يرجى كتابة تفاصيل الشكوى';
                            if (trimmed.length > 4000)
                              return 'الرسالة طويلة جداً';
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: AppTheme.navyButton(),
                            onPressed: _isSubmitting ? null : _handleSubmit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('إرسال الشكوى بأمان'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // History Section
                Text(
                  'شكاوى سابقة',
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FutureBuilder<List<ComplaintItem>>(
                  future: _complaintsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final list = snapshot.data ?? [];
                    if (list.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          'لا توجد شكاوى سابقة مسجلة.',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final item = list[index];
                        Color badgeColor;
                        Color textColor;
                        switch (item.status) {
                          case 'RESOLVED':
                            badgeColor = Colors.green.shade100;
                            textColor = Colors.green.shade800;
                            break;
                          case 'IN_PROGRESS':
                            badgeColor = Colors.blue.shade100;
                            textColor = Colors.blue.shade800;
                            break;
                          case 'NEW':
                          default:
                            badgeColor = Colors.amber.shade100;
                            textColor = Colors.amber.shade900;
                            break;
                        }

                        return Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.full,
                                  ),
                                ),
                                child: Text(
                                  item.statusLabel,
                                  style: AppTypography.labelMd.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'التصنيف: ${item.category}',
                                      style: AppTypography.bodyMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (item.createdAt != null)
                                      Text(
                                        'تاريخ الإرسال: ${item.createdAt!.toLocal().toString().split('.').first}',
                                        style: AppTypography.labelMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '#${item.id}',
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
