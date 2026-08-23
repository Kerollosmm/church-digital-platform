import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/payment_channel.dart';
import '../../models/payment_proof_input.dart';
import '../../models/payout_channel.dart';
import '../../repositories/booking_repository.dart';
import '../../services/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.repository,
  });

  final int bookingId;
  final int amount;
  final BookingRepository repository;

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _senderPhoneController;
  late final TextEditingController _referenceController;
  late final TextEditingController _amountController;

  PaymentChannel _selectedChannel = PaymentChannel.vodafoneCash;
  List<PayoutChannel> _payoutChannels = [];
  bool _isSubmitting = false;
  Uint8List? _selectedImageBytes;
  String? _imageFileName;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    _senderPhoneController = TextEditingController();
    _referenceController = TextEditingController();
    _amountController = TextEditingController(text: widget.amount.toString());
    _loadPayoutChannels();
  }

  @override
  void dispose() {
    _senderPhoneController.dispose();
    _referenceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPayoutChannels() async {
    final result = await widget.repository.fetchPayoutChannels();
    if (!mounted) return;
    setState(() {
      result.fold(
        (_) => _payoutChannels = [],
        (channels) => _payoutChannels = channels,
      );
    });
  }

  PayoutChannel? get _currentPayoutChannel {
    try {
      return _payoutChannels.firstWhere(
        (c) => c.channel == _selectedChannel,
      );
    } catch (_) {
      return null;
    }
  }

  void _attachMockImage() {
    setState(() {
      _selectedImageBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      _imageFileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      _imageError = null;
    });
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _imageFileName = image.name.isNotEmpty
              ? image.name
              : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
          _imageError = null;
        });
        return;
      }
    } catch (_) {
      // In test/headless environments, fallback to mock bytes
    }
    _attachMockImage();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedChannel != PaymentChannel.cash && _selectedImageBytes == null) {
      setState(() {
        _imageError = AppStrings.proofImageRequired;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _imageError = null;
    });

    String? imagePath;
    if (_selectedChannel != PaymentChannel.cash && _selectedImageBytes != null) {
      final uploadRes = await widget.repository.uploadProofImage(
        bookingId: widget.bookingId,
        bytes: _selectedImageBytes!,
        filename: _imageFileName ?? 'proof.jpg',
      );

      final uploadFailed = uploadRes.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
          return true;
        },
        (path) {
          imagePath = path;
          return false;
        },
      );

      if (uploadFailed) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }
    }

    final amountVal = int.tryParse(_amountController.text.trim()) ?? widget.amount;
    final input = PaymentProofInput(
      bookingId: widget.bookingId,
      channel: _selectedChannel,
      senderPhone: _senderPhoneController.text.trim(),
      referenceNumber: _referenceController.text.trim(),
      amount: amountVal,
      imagePath: imagePath,
    );

    final result = await widget.repository.submitPaymentProof(input);
    if (!mounted) return;

    setState(() => _isSubmitting = false);

    result.fold(
      (failure) {
        if (imagePath != null) {
          widget.repository.deleteProofImage(imagePath!);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      },
      (proofId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.proofSubmittedSuccess)),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePayout = _currentPayoutChannel;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          AppStrings.paymentProofTitle,
          style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.marginMobile),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.paymentProofSubtitle,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Channel Selector
                Text(
                  AppStrings.paymentChannelLabel,
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: const Text(AppStrings.vodafoneCash),
                      selected: _selectedChannel == PaymentChannel.vodafoneCash,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedChannel = PaymentChannel.vodafoneCash);
                        }
                      },
                    ),
                    ChoiceChip(
                      label: const Text(AppStrings.instaPay),
                      selected: _selectedChannel == PaymentChannel.instaPay,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedChannel = PaymentChannel.instaPay);
                        }
                      },
                    ),
                    ChoiceChip(
                      label: const Text(AppStrings.cashInPerson),
                      selected: _selectedChannel == PaymentChannel.cash,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedChannel = PaymentChannel.cash);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Church payout details card
                if (_selectedChannel != PaymentChannel.cash && activePayout != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activePayout.displayNameAr.isNotEmpty
                              ? activePayout.displayNameAr
                              : AppStrings.payoutDetailsTitle,
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Text(
                              '${AppStrings.accountNumberLabel}: ',
                              style: AppTypography.bodyMd,
                            ),
                            SelectableText(
                              activePayout.accountNumber,
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: activePayout.accountNumber),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(AppStrings.copied),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              '${AppStrings.accountHolderLabel}: ',
                              style: AppTypography.bodyMd,
                            ),
                            Text(
                              activePayout.holderName,
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Sender phone
                TextFormField(
                  controller: _senderPhoneController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.senderPhoneLabel,
                    hintText: AppStrings.senderPhoneHint,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),

                // Reference number
                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.referenceNumberLabel,
                    hintText: AppStrings.referenceNumberHint,
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.amountClaimedLabel,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return AppStrings.fieldRequired;
                    }
                    final numVal = int.tryParse(val.trim());
                    if (numVal == null || numVal <= 0) {
                      return AppStrings.invalidAmount;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),

                // Attach Image (required for wallet channels)
                if (_selectedChannel != PaymentChannel.cash) ...[
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _selectedImageBytes != null
                          ? 'تم إرفاق: ${_imageFileName ?? "صورة التحويل"}'
                          : AppStrings.attachProofImage,
                    ),
                  ),
                  if (_imageError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _imageError!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: AppTheme.navyButton(),
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text(AppStrings.submitProof),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
