import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'billing_controller.dart';
import 'billing_models.dart';
import 'premium_config.dart';

Future<void> showProUpgrade(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
  );
}

class ProUpgradeScreen extends ConsumerWidget {
  const ProUpgradeScreen({super.key});

  static final Uri _manageSubscriptionUri = Uri.parse(
    'https://play.google.com/store/account/subscriptions'
    '?sku=${PremiumConfig.proProductId}'
    '&package=com.baishalya.surveycam',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = PremiumConfig.freeLaunchMode
        ? const BillingState(isInitializing: false)
        : ref.watch(billingControllerProvider);
    final controller = PremiumConfig.freeLaunchMode
        ? null
        : ref.read(billingControllerProvider.notifier);
    final product = billing.product;
    final hasTrial = product?.hasFreeTrial == true;
    final isLaunchOffer =
        hasTrial && product?.offerId == PremiumConfig.launchOfferId;
    final trialLabel = _trialLabel(product?.freeTrialPeriod);
    final busy = billing.isInitializing ||
        billing.isRestoring ||
        billing.purchasePending;
    final canSubscribe = !PremiumConfig.freeLaunchMode &&
        billing.storeAvailable &&
        billing.verificationConfigured &&
        product != null &&
        !busy &&
        !billing.isPro;

    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'SurveyCam Pro',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            _OfferHero(
              billing: billing,
              product: product,
              isLaunchOffer: isLaunchOffer,
              trialLabel: trialLabel,
            ),
            const SizedBox(height: 18),
            if (!billing.isPro && !PremiumConfig.freeLaunchMode)
              _PriceSummary(
                product: product,
                hasTrial: hasTrial,
                trialLabel: trialLabel,
              ),
            if (!billing.isPro && !PremiumConfig.freeLaunchMode)
              const SizedBox(height: 22),
            const Text(
              'Everything your field proof needs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The camera and default white/black overlay colors stay free. Pro unlocks the professional workflow.',
              style: TextStyle(
                color: Color(0xFFAAB7C8),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            const _BenefitGrid(),
            if (billing.error != null) ...[
              const SizedBox(height: 18),
              _StatusCard(message: billing.error!, isError: true),
            ] else if (!PremiumConfig.freeLaunchMode &&
                !billing.isInitializing &&
                !billing.verificationConfigured) ...[
              const SizedBox(height: 18),
              const _StatusCard(
                message:
                    'Payments are not configured in this build yet. Update SurveyCam before subscribing.',
                isError: true,
              ),
            ] else if (billing.message != null) ...[
              const SizedBox(height: 18),
              _StatusCard(message: billing.message!),
            ],
            const SizedBox(height: 22),
            _PrimaryAction(
              billing: billing,
              product: product,
              busy: busy,
              canSubscribe: canSubscribe,
              trialLabel: trialLabel,
              onSubscribe: controller?.buyPro ?? _noAction,
              onManage: _openPlaySubscriptions,
            ),
            if (!PremiumConfig.freeLaunchMode && !billing.isPro) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('pro-restore-button'),
                onPressed: busy ? null : controller?.restore,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF31445D)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.restore_rounded, size: 19),
                label: const Text('Restore purchase'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openPlaySubscriptions,
              child: const Text('Manage in Google Play'),
            ),
            const SizedBox(height: 4),
            _LegalCopy(product: product),
          ],
        ),
      ),
    );
  }

  static Future<void> _openPlaySubscriptions() async {
    await launchUrl(
      _manageSubscriptionUri,
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<void> _noAction() async {}
}

class _OfferHero extends StatelessWidget {
  const _OfferHero({
    required this.billing,
    required this.product,
    required this.isLaunchOffer,
    required this.trialLabel,
  });

  final BillingState billing;
  final BillingProduct? product;
  final bool isLaunchOffer;
  final String trialLabel;

  @override
  Widget build(BuildContext context) {
    final title = switch ((
      billing.isPro,
      PremiumConfig.freeLaunchMode,
      isLaunchOffer,
      billing.isInitializing,
    )) {
      (true, _, _, _) => 'Your Pro workspace\nis active',
      (_, true, _, _) => 'Pro is included\nduring free launch',
      (_, _, true, _) => '$trialLabel free',
      (_, _, _, true) => 'Checking your\nlaunch offer',
      _ => 'Upgrade your\nfield workflow',
    };
    final subtitle = billing.isPro
        ? 'Thank you for supporting SurveyCam.'
        : PremiumConfig.freeLaunchMode
            ? 'Try every prepared Pro feature before paid access is switched on.'
            : isLaunchOffer
                ? 'Join during the limited launch window. Pay nothing today, then keep Pro at the Google Play renewal price.'
                : 'Organize, brand, and export trusted field evidence from one camera.';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A35D6), Color(0xFF1267C8), Color(0xFF0A9B92)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3979E8).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -38,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: 36,
            bottom: -52,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.09),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFFFDC73),
                        size: 27,
                      ),
                    ),
                    const Spacer(),
                    _HeroBadge(
                      label: billing.isPro
                          ? 'ACTIVE'
                          : isLaunchOffer
                              ? '6-MONTH LAUNCH WINDOW'
                              : 'SURVEYCAM PRO',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.04,
                    letterSpacing: -0.9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                if (isLaunchOffer) ...[
                  const SizedBox(height: 18),
                  _LaunchDeadline(deadline: PremiumConfig.launchOfferEndsAt),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F).withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LaunchDeadline extends StatelessWidget {
  const _LaunchDeadline({required this.deadline});

  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOpen = deadline == null || now.isBefore(deadline!);
    final remainingDays = deadline == null
        ? null
        : deadline!.difference(now).inDays.clamp(0, 9999) + 1;
    final text = deadline == null
        ? 'Available for a limited time'
        : isOpen
            ? 'Join by ${_shortDate(deadline!)}'
                '${remainingDays == null ? '' : '  •  $remainingDays days left'}'
            : 'Google Play confirms current offer availability';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F).withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({
    required this.product,
    required this.hasTrial,
    required this.trialLabel,
  });

  final BillingProduct? product;
  final bool hasTrial;
  final String trialLabel;

  @override
  Widget build(BuildContext context) {
    final loading = product == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101D2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF233851)),
      ),
      child: loading
          ? const Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading Google Play price…',
                  style: TextStyle(color: Color(0xFFAAB7C8)),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _PriceColumn(
                    eyebrow: hasTrial ? 'TODAY' : 'GOOGLE PLAY PRICE',
                    price: hasTrial ? '₹0' : product!.displayPrice,
                    detail: hasTrial ? 'for $trialLabel' : 'annual plan',
                    highlight: true,
                  ),
                ),
                Container(
                  width: 1,
                  height: 54,
                  color: const Color(0xFF2B415A),
                ),
                Expanded(
                  child: _PriceColumn(
                    eyebrow: hasTrial ? 'AFTER TRIAL' : 'RENEWS',
                    price: product!.renewalPrice,
                    detail: _renewalLabel(product!.renewalPeriod),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({
    required this.eyebrow,
    required this.price,
    required this.detail,
    this.highlight = false,
  });

  final String eyebrow;
  final String price;
  final String detail;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Color(0xFF7F91A8),
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlight ? const Color(0xFF6DE6C1) : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            detail,
            style: const TextStyle(color: Color(0xFFAAB7C8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid();

  static const _benefits = [
    (
      Icons.palette_rounded,
      'Pro overlay colors',
      'Brand-ready color choices',
    ),
    (
      Icons.folder_copy_rounded,
      'Project folders',
      'Keep every site organized',
    ),
    (
      Icons.picture_as_pdf_rounded,
      'PDF proof reports',
      'Share professional evidence',
    ),
    (
      Icons.branding_watermark_rounded,
      'Custom branding',
      'Your logo, name, and style',
    ),
    (
      Icons.note_alt_rounded,
      'Saved templates',
      'Faster repeat field notes',
    ),
    (
      Icons.verified_user_rounded,
      'Proof verification',
      'Tamper-evident proof IDs',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 330;
        final width =
            twoColumns ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _benefits
              .map(
                (benefit) => SizedBox(
                  width: width,
                  child: _Benefit(
                    icon: benefit.$1,
                    title: benefit.$2,
                    detail: benefit.$3,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF101D2D),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF1D3148)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF72A7FF), size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8799AE),
              fontSize: 10.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.billing,
    required this.product,
    required this.busy,
    required this.canSubscribe,
    required this.trialLabel,
    required this.onSubscribe,
    required this.onManage,
  });

  final BillingState billing;
  final BillingProduct? product;
  final bool busy;
  final bool canSubscribe;
  final String trialLabel;
  final Future<void> Function() onSubscribe;
  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    final label = billing.isPro
        ? 'Manage subscription'
        : PremiumConfig.freeLaunchMode
            ? 'Pro included during free launch'
            : product?.hasFreeTrial == true
                ? 'Start $trialLabel free trial'
                : product == null
                    ? 'Subscribe to Pro'
                    : 'Subscribe for ${product!.displayPrice}';
    final onPressed = billing.isPro
        ? onManage
        : PremiumConfig.freeLaunchMode
            ? () async => Navigator.of(context).maybePop()
            : canSubscribe
                ? onSubscribe
                : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          colors: [Color(0xFF6E55F7), Color(0xFF2B8DED)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B7DFF).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: FilledButton.icon(
        key: const Key('pro-primary-cta'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: const Color(0xFF26374A),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF8290A0),
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        icon: busy && !PremiumConfig.freeLaunchMode
            ? const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                billing.isPro
                    ? Icons.manage_accounts_rounded
                    : Icons.workspace_premium_rounded,
              ),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFF7E8A) : const Color(0xFF72A7FF);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.info_outline_rounded : Icons.check_circle_outline,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, height: 1.35, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalCopy extends StatelessWidget {
  const _LegalCopy({required this.product});

  final BillingProduct? product;

  @override
  Widget build(BuildContext context) {
    final trial = product?.hasFreeTrial == true
        ? '${_trialLabel(product!.freeTrialPeriod)} free for eligible new subscribers, then ${product!.renewalPrice} ${_renewalLabel(product!.renewalPeriod)}. '
        : '';
    return Text(
      'Payment and eligibility are confirmed by Google Play. $trial'
      'The subscription renews automatically unless cancelled in Google Play before renewal. You keep access until the paid or trial period ends.',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF687A8F),
        fontSize: 10.5,
        height: 1.45,
      ),
    );
  }
}

String _trialLabel(String? isoPeriod) {
  final match = RegExp(r'^P(\d+)([DMY])$').firstMatch(isoPeriod ?? '');
  if (match == null) return 'limited-time';
  final amount = int.tryParse(match.group(1)!) ?? 1;
  final unit = switch (match.group(2)) {
    'D' => amount == 1 ? 'day' : 'days',
    'M' => amount == 1 ? 'month' : 'months',
    'Y' => amount == 1 ? 'year' : 'years',
    _ => 'period',
  };
  return '$amount $unit';
}

String _renewalLabel(String? isoPeriod) {
  final period = _trialLabel(isoPeriod);
  return period == 'limited-time' ? 'per billing period' : 'every $period';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
