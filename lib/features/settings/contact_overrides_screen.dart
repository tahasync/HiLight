import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/contact_override_store.dart';

/// Per-contact pattern assignments (prd-v1.2.md Â§2): pick a contact, assign
/// a preset; calls from that contact fire it instead of the generic
/// incoming-call preset.
///
/// Permissions discipline: READ_CONTACTS is requested only when the user
/// taps "Add contact" — an explanation dialog precedes the system runtime
/// dialog, and the Contacts picker opens only after a grant.
class ContactOverridesScreen extends StatefulWidget {
  const ContactOverridesScreen({required this.presets, super.key});

  /// Built-in + custom presets available for assignment.
  final List<HilightAnimation> presets;

  @override
  State<ContactOverridesScreen> createState() =>
      _ContactOverridesScreenState();
}

class _ContactOverridesScreenState extends State<ContactOverridesScreen> {
  static const _contacts = MethodChannel('hilight/contacts');

  final ContactOverrideStore _store = ContactOverrideStore();
  List<ContactOverride>? _overrides;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final overrides = await _store.loadAll();
    if (!mounted) return;
    setState(() => _overrides = overrides);
  }

  String? _presetName(String id) {
    for (final preset in widget.presets) {
      if (preset.id == id) return preset.name;
    }
    return null;
  }

  Future<void> _addOverride() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 1. Explain why (prd.md Â§23), then ask — only now.
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Contacts access needed'),
          content: const Text(
            'To assign a pattern to one of your contacts, HiLight needs '
            'permission to read contact names and numbers. This is used '
            'only to recognise callers you assign here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;

      // 2. Runtime permission request — the exact enable moment.
      final granted =
          await _contacts.invokeMethod<bool>('requestReadContacts') ?? false;
      if (!granted || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Contacts permission is required to assign patterns.'),
          ));
        }
        return;
      }

      // 3. System Contacts picker.
      final uri =
          await _contacts.invokeMethod<String>('pickContact');
      if (uri == null || !mounted) return;

      // 4. Read the picked row and store the assignment.
      final details = await _contacts
          .invokeMethod<Map<Object?, Object?>>('readPickedContact', {
        'uri': uri,
      });
      if (details == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not read that contact.'),
          ));
        }
        return;
      }
      final presetId = await _selectPreset(null);
      if (presetId == null || !mounted) return;

      Haptics.medium();
      await _store.upsert(ContactOverride(
        lookupKey: details['lookupKey'] as String? ?? '',
        displayName: details['displayName'] as String? ?? '',
        number: details['number'] as String? ?? '',
        presetId: presetId,
      ));
      await _reload();
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contacts are unavailable on this device.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPreset(ContactOverride override) async {
    final presetId = await _selectPreset(override.presetId);
    if (presetId == null) return;
    Haptics.light();
    await _store.upsert(override.copyWith(presetId: presetId));
    await _reload();
  }

  Future<void> _remove(ContactOverride override) async {
    Haptics.medium();
    await _store.remove(override.lookupKey);
    await _reload();
  }

  Future<String?> _selectPreset(String? current) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Assign preset'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              children: [
                for (final preset in widget.presets)
                  RadioListTile<String>(
                    value: preset.id,
                    title: Text(preset.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overrides = _overrides;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact overrides')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addOverride,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add contact'),
      ),
      body: overrides == null
          ? const Center(child: CircularProgressIndicator())
          : overrides.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No contact patterns yet.\n'
                      'Calls from an assigned contact flash their own '
                      'preset; everyone else uses the generic one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final override in overrides)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassSurface(
                          blur: false,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _editPreset(override),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 8, 12),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  const Padding(
                                    padding:
                                        EdgeInsets.only(right: 14),
                                    child: Icon(Icons.phone_outlined),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          override.displayName.isEmpty
                                              ? '(unnamed contact)'
                                              : override.displayName,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme.bodyLarge,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          override.number,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Chip(
                                          visualDensity:
                                              VisualDensity.compact,
                                          label: Text(
                                            _presetName(
                                                    override.presetId) ??
                                                override.presetId,
                                            style: Theme.of(context)
                                                .textTheme.labelMedium,
                                          ),
                                          avatar:
                                              const Icon(Icons.bolt,
                                                  size: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline),
                                    tooltip: 'Remove',
                                    onPressed: () => _remove(override),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Matching ignores country-code differences. '
                        'Caller identity comes from call notifications '
                        'while the screen is off; nothing is stored '
                        'beyond what you assign here.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
