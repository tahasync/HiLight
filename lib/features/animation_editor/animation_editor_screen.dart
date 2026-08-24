import 'package:flutter/material.dart' hide Easing;

import '../../core/haptics.dart';
import '../../core/motion/easing.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/torch_service.dart';
import '../home/widgets/hero_flash_visual.dart';
import '../settings/app_settings_controller.dart';
import 'custom_animation_store.dart';
import 'custom_animation_validation.dart';
import 'editor_controller.dart';
import 'stored_custom_animation.dart';

/// Create/edit screen for custom animations (prd-v1.1.md Â§3). Pops with the
/// saved [StoredCustomAnimation] on save, or null on cancel/delete.
class AnimationEditorScreen extends StatefulWidget {
  const AnimationEditorScreen({
    required this.settings,
    this.initial,
    super.key,
  });

  final AppSettingsController settings;
  final StoredCustomAnimation? initial;

  @override
  State<AnimationEditorScreen> createState() => _AnimationEditorScreenState();
}

class _AnimationEditorScreenState extends State<AnimationEditorScreen> {
  late final EditorController _controller = EditorController(
    TorchService(),
    widget.settings,
    initial: widget.initial,
  );
  late final TextEditingController _nameField =
      TextEditingController(text: _controller.draft.name);

  @override
  void dispose() {
    _nameField.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    Haptics.medium();
    final entry = await _controller.saveTo(CustomAnimationStore());
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  Future<void> _delete() async {
    Haptics.medium();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete animation?'),
        content: Text(
            '"${_controller.draft.name}" will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteFrom(CustomAnimationStore());
    if (!mounted) return;
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final controller = _controller;
        final colorScheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: Text(controller.isEditingExisting
              ? 'Edit animation'
              : 'New animation')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  if (controller.isEditingExisting)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: controller.isValid ? _save : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.07),
                  colorScheme.surface,
                  colorScheme.primary.withValues(alpha: 0.05),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                GlassSurface(
                  borderRadius: GlassTokens.heroRadius,
                  child: HeroFlashVisual(
                    animation: controller.displayAnimation,
                    playing: controller.isPlaying,
                    brightness: widget.settings.brightness,
                    speed: widget.settings.speed,
                    repeatCount: widget.settings.repeatCount,
                    session: controller.playSession,
                    startedAt: controller.previewStartedAt,
                  ),
                ),
                Text(
                  controller.statusText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: controller.torchError != null
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      textStyle: Theme.of(context).textTheme.titleMedium,
                    ),
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 30,
                    ),
                    label: Text(controller.isPlaying ? 'Stop' : 'Preview'),
                    onPressed:
                        controller.canPlay && controller.isValid
                            ? controller.togglePreview
                            : null,
                  ),
                ),
                const SizedBox(height: 16),
                _DetailsCard(controller: controller, nameField: _nameField),
                const SizedBox(height: 12),
                _TimelineCard(controller: controller),
                const SizedBox(height: 12),
                _EasingCard(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.controller, required this.nameField});

  final EditorController controller;
  final TextEditingController nameField;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: nameField,
              onChanged: controller.setName,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Duration',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${controller.draft.durationMs} ms',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            Slider(
              value: controller.draft.durationMs.toDouble(),
              min: CustomAnimationLimits.minDurationMs.toDouble(),
              max: CustomAnimationLimits.maxDurationMs.toDouble(),
              divisions:
                  (CustomAnimationLimits.maxDurationMs -
                          CustomAnimationLimits.minDurationMs) ~/
                      50,
              label: '${controller.draft.durationMs} ms',
              onChanged: (value) =>
                  controller.setDurationMs(value.round()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Keyframes',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('${draft.keyframes.length} / '
                    '${CustomAnimationLimits.maxKeyframes}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (controller.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final issue in controller.issues)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_issueMessage(issue),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.error,
                                )),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            for (var i = 0; i < draft.keyframes.length; i++)
              _KeyframeRow(
                controller: controller,
                index: i,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: draft.keyframes.length <
                        CustomAnimationLimits.maxKeyframes
                    ? controller.addKeyframeAtEnd
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add keyframe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyframeRow extends StatelessWidget {
  const _KeyframeRow({required this.controller, required this.index});

  final EditorController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final keyframe = controller.draft.keyframes[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text('#${index + 1}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '10 ms earlier',
                onPressed: () => controller.nudgeKeyframeTime(index, -10),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              SizedBox(
                width: 76,
                child: Text('${keyframe.time.inMilliseconds} ms',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '10 ms later',
                onPressed: () => controller.nudgeKeyframeTime(index, 10),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove keyframe',
                onPressed: () => controller.removeKeyframeAt(index),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 28),
              Expanded(
                child: Slider(
                  value: keyframe.intensity,
                  onChanged: (value) =>
                      controller.setKeyframeIntensity(index, value),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(keyframe.intensity * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }
}

class _EasingCard extends StatelessWidget {
  const _EasingCard({required this.controller});

  final EditorController controller;

  static const _labels = <Easing, String>{
    Easing.linear: 'Linear',
    Easing.easeIn: 'Ease In',
    Easing.easeOut: 'Ease Out',
    Easing.easeInOut: 'Ease In Out',
    Easing.smoothSine: 'Smooth Sine',
  };

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Easing', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Applied between every keyframe pair.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            DropdownMenu<Easing>(
              expandedInsets: EdgeInsets.zero,
              initialSelection: controller.draft.easing,
              dropdownMenuEntries: [
                for (final easing in Easing.values)
                  DropdownMenuEntry(
                    value: easing,
                    label: _labels[easing] ?? easing.name,
                  ),
              ],
              onSelected: (easing) {
                if (easing != null) controller.setEasing(easing);
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _issueMessage(CustomAnimationIssue issue) {
  return switch (issue) {
    CustomAnimationIssue.tooFewKeyframes =>
      'Add at least ${CustomAnimationLimits.minKeyframes} keyframes.',
    CustomAnimationIssue.tooManyKeyframes =>
      'Use at most ${CustomAnimationLimits.maxKeyframes} keyframes.',
    CustomAnimationIssue.unsortedKeyframes =>
      'Keyframe times must strictly increase.',
    CustomAnimationIssue.durationTooShort =>
      'Duration must be at least ${CustomAnimationLimits.minDurationMs} ms.',
    CustomAnimationIssue.durationTooLong =>
      'Duration must be at most ${CustomAnimationLimits.maxDurationMs} ms.',
    CustomAnimationIssue.intensityOutOfRange =>
      'Intensity must stay between 0% and 100%.',
  };
}
