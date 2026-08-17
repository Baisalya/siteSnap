import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_controller.dart';
import 'app_update_models.dart';

class MandatoryUpdateScreen extends ConsumerWidget {
  const MandatoryUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final availableBuild = state.info?.availableBuildNumber;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.system_update_rounded,
                    color: Colors.blueAccent,
                    size: 88,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    availableBuild == null
                        ? 'Install the latest SurveyCam version to continue.'
                        : 'SurveyCam build $availableBuild contains required reliability and security improvements.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 20),
                    _UpdateMessage(message: state.error!, isError: true),
                  ] else if (state.message != null) ...[
                    const SizedBox(height: 20),
                    _UpdateMessage(message: state.message!),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.isUpdating
                          ? null
                          : controller.startRequiredUpdate,
                      icon: state.isUpdating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        state.isUpdating ? 'Updating…' : 'Update now',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed:
                        state.isUpdating ? null : controller.openStoreListing,
                    child: const Text('Open Google Play'),
                  ),
                  TextButton(
                    onPressed:
                        state.isUpdating ? null : controller.checkForUpdate,
                    child: const Text('I updated — check again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OptionalUpdateBanner extends ConsumerWidget {
  const OptionalUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    if (state.requirement != AppUpdateRequirement.optional) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(appUpdateControllerProvider.notifier);

    return SafeArea(
      child: Material(
        color: const Color(0xFF172A46),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'A new SurveyCam update is available.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed:
                    state.isUpdating ? null : controller.startOptionalUpdate,
                child: Text(state.isUpdating ? 'Updating…' : 'Update'),
              ),
              IconButton(
                tooltip: 'Not now',
                onPressed:
                    state.isUpdating ? null : controller.dismissOptionalUpdate,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateMessage extends StatelessWidget {
  const _UpdateMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : Colors.lightBlueAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, height: 1.35),
      ),
    );
  }
}
