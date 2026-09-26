import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_controller.dart';
import 'billing_models.dart';
import 'premium_config.dart';
import 'pro_upgrade_screen.dart';

/// Always opens membership details directly, never through a premium gate:
/// subscribers already pass those gates and otherwise cannot reach this page.
class ProMembershipEntry extends ConsumerWidget {
  const ProMembershipEntry({
    super.key,
    this.compact = false,
    this.enabled = true,
  });

  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(proMembershipBillingProvider);
    final checking = billing.isInitializing || billing.isRestoring;
    final String status;
    final String detail;
    if (billing.isPro) {
      status = 'Pro Active';
      detail = checking
          ? 'Refreshing your subscription status…'
          : billing.entitlementSource == EntitlementSource.cached
              ? 'Offline Pro access · View membership details'
              : 'Ad-free benefits · View plan and validity';
    } else if (checking) {
      status = 'Checking Pro';
      detail = 'Restoring your Google Play subscription…';
    } else if (billing.purchasePending) {
      status = 'Payment pending';
      detail = 'Waiting for confirmation from Google Play';
    } else if (PremiumConfig.freeLaunchMode) {
      status = 'Pro included';
      detail = 'Features included during free launch';
    } else if (billing.error != null) {
      status = 'Check Pro status';
      detail = 'Open membership details to check or restore access';
    } else {
      status = 'Get Pro';
      detail = 'View plans or restore an existing subscription';
    }

    final accent =
        billing.isPro ? const Color(0xFF74E7C1) : const Color(0xFFFFD76A);
    final radius = BorderRadius.circular(compact ? 24 : 16);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'My Subscription. $status. $detail',
      excludeSemantics: true,
      onTap: enabled ? () => showProUpgrade(context) : null,
      child: Material(
        color: compact ? const Color(0xD9101D2D) : const Color(0xFF101D2D),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          key: Key(
              compact ? 'camera-pro-membership' : 'settings-pro-membership'),
          borderRadius: radius,
          onTap: enabled ? () => showProUpgrade(context) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 8 : 14,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  billing.isPro
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_rounded,
                  color: accent,
                  size: compact ? 18 : 26,
                ),
                SizedBox(width: compact ? 7 : 12),
                Flexible(
                  fit: compact ? FlexFit.loose : FlexFit.tight,
                  child: compact
                      ? Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'My Subscription',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(status, style: TextStyle(color: accent)),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              style: const TextStyle(
                                color: Color(0xFFAAB7C8),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white54),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
