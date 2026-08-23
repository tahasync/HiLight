import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// GitHub-Releases-backed update check, mirroring the Foam Shop POS flow:
/// compare the installed version against the latest release tag, then offer
/// a Material 3 dialog with the changelog and a link to the release page.
class AppUpdateConfig {
  static const repoOwner = 'tahasync';
  static const repoName = 'HiLight';
  static const apiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const latestReleaseUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest';
}

class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.body,
  });

  final String tagName;
  final String htmlUrl;
  final String body;
}

/// Returns the latest release info, or null when offline / on any failure —
/// an update check must never disturb a normal launch.
Future<UpdateInfo?> checkForUpdate() async {
  try {
    final response = await http.get(
      Uri.parse(AppUpdateConfig.apiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = data['tag_name'] as String? ?? '';
    if (tag.isEmpty) return null;
    return UpdateInfo(
      tagName: tag,
      htmlUrl: data['html_url'] as String? ?? AppUpdateConfig.latestReleaseUrl,
      body: data['body'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

/// Whether [remote] (e.g. `v1.2.0`) is newer than [installed] (e.g. `1.1.0`).
bool isNewerVersion(String installed, String remote) {
  final iParts = installed.replaceAll(RegExp(r'^v'), '').split('.');
  final rParts = remote.replaceAll(RegExp(r'^v'), '').split('.');
  final maxLen = iParts.length > rParts.length ? iParts.length : rParts.length;
  for (var i = 0; i < maxLen; i++) {
    final iv = int.tryParse(iParts.length > i ? iParts[i] : '0') ?? 0;
    final rv = int.tryParse(rParts.length > i ? rParts[i] : '0') ?? 0;
    if (rv > iv) return true;
    if (rv < iv) return false;
  }
  return false;
}

String formatChangelog(String rawNotes) {
  const fallback = 'No changelog available for this release.';
  final clean = rawNotes
      .replaceAll(RegExp(r'\*\*Full Changelog\*\*:\s*https?://\S+'), '')
      .replaceAll(RegExp(r'https?://github\.com/\S+'), '')
      .replaceAll('**', '')
      .trim();
  return clean.isEmpty ? fallback : clean;
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
  final pkg = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  final installed = pkg.version;
  final colorScheme = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.system_update_rounded,
                  size: 26, color: colorScheme.onPrimary),
            ),
            const SizedBox(height: 12),
            Text('Update Available',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VersionPill(label: 'v$installed', muted: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('\u2192',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ),
                _VersionPill(label: update.tagName, muted: false),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("What's New",
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.05,
                          color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 200,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        formatChangelog(update.body),
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                            height: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await launchUrl(Uri.parse(update.htmlUrl),
                      mode: LaunchMode.externalApplication);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Update Now',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Remind me later',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.label, required this.muted});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: muted
            ? colorScheme.surfaceContainerLow
            : colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: muted
            ? Border.all(color: colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: muted ? colorScheme.onSurfaceVariant : colorScheme.primary,
        ),
      ),
    );
  }
}
