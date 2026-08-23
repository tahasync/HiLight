import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Single source of truth for torch playback state, bridged to the Android
/// Quick Settings tile over `hilight/tile_control` (prd-v1.1.md §4).
///
/// Ownership model: whichever component starts a playback (the home screen's
/// [HomeController] or the tile-driven default-preset player) registers a
/// stop hook; a toggle stops the current owner first, otherwise it asks the
/// registered external starter to begin playback. Every transition is
/// published to Kotlin so the tile always mirrors the engine's actual state,
/// including natural completion.
class PlaybackCoordinator {
  PlaybackCoordinator._internal();

  static final PlaybackCoordinator instance = PlaybackCoordinator._internal();

  static const MethodChannel _channel = MethodChannel('hilight/tile_control');

  bool _attached = false;
  Object? _owner;
  Future<void> Function()? _stopOwner;
  Future<void> Function()? _externalStart;
  Future<void> Function()? _tileStop;

  /// Inbound trigger events from Kotlin (notification listener today,
  /// charging broadcasts later — prd-v1.2.md §2/§4). The handler owns all
  /// decision logic; the coordinator only forwards the raw arguments map.
  Future<void> Function(Map<Object?, Object?> arguments)? _triggerHandler;

  /// Idempotent; installs the inbound handler for tile requests.
  void attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'toggle':
          await toggle();
        case 'refreshState':
          _publish(force: true);
        case 'tileStop':
          await _tileStop?.call();
        case 'triggerEvent':
          final arguments = call.arguments;
          if (arguments is Map) {
            await _triggerHandler
                ?.call(Map<Object?, Object?>.from(arguments));
          }
        default:
          throw MissingPluginException(
              'unknown hilight/tile_control method ${call.method}');
      }
    });
  }

  /// Registers the handler for native trigger events. The latest
  /// registration wins; call once per isolate during startup.
  void registerTriggerHandler(
    Future<void> Function(Map<Object?, Object?> arguments)? handler,
  ) {
    _triggerHandler = handler;
  }

  /// Registers how the platform can stop tile-owned playback (the Quick
  /// Settings panel closing must safely cancel a tile-triggered animation —
  /// the cached-app freezer would otherwise suspend the completion timer and
  /// leave the torch lit).
  void registerTileStop(Future<void> Function() stop) {
    _tileStop = stop;
  }

  /// Stops playback only when [owner] currently owns it. Returns whether a
  /// stop was performed.
  Future<bool> requestStop(Object owner) async {
    if (!identical(_owner, owner)) return false;
    final stop = _stopOwner;
    if (stop != null) await stop();
    return true;
  }

  /// Whether any playback currently owns the torch.
  bool get isActive => _stopOwner != null;

  /// Called by an owner right after it successfully starts playback.
  void beginOwnership(Object owner, Future<void> Function() stop) {
    _owner = owner;
    _stopOwner = stop;
    _publish();
  }

  /// Called when playback ends for any reason (user stop, cancellation,
  /// error, or natural completion). No-op if [owner] is not current.
  void endOwnership(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _stopOwner = null;
    _publish();
  }

  /// Registers how a tile tap starts the default animation when nothing is
  /// playing (prd-v1.1.md §4).
  void registerExternalStart(Future<void> Function() start) {
    _externalStart = start;
  }

  /// Stops the current playback if one exists; otherwise starts the default
  /// animation through the registered external starter.
  Future<void> toggle() async {
    final stop = _stopOwner;
    if (stop != null) {
      await stop();
      return;
    }
    final start = _externalStart;
    if (start != null) {
      await start();
    }
  }

  /// Re-publishes the current state (e.g. right after a fresh headless
  /// engine boots and Kotlin is listening).
  void refreshState() => _publish(force: true);

  void _publish({bool force = false}) {
    if (!force && !_attached) return;
    if (kDebugMode) {
      print('HiLight tile: stateChanged active=${_stopOwner != null}');
    }
    _channel
        .invokeMethod('stateChanged', <String, Object?>{
          'active': _stopOwner != null,
        })
        .catchError((_) {
      // The Android side may be gone (e.g. headless engine teardown);
      // a failed publish never breaks local playback state.
    });
  }

  /// Clears all ownership and handlers between tests.
  @visibleForTesting
  void resetForTest() {
    _owner = null;
    _stopOwner = null;
    _externalStart = null;
    // The channel handler stays attached; harmless under mocked messengers.
  }
}
