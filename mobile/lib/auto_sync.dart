import 'dart:async';
import 'package:flutter/material.dart';
import 'remote.dart';
import 'store.dart';
import 'workspace.dart';

/// Optional foreground synchronization with scoped consent and durable retry state.
class AutoSyncHost extends StatefulWidget {
  final AppStore store;
  final Widget child;
  final RemoteSync Function(AppStore)? remoteFactory;
  const AutoSyncHost(
      {super.key,
      required this.store,
      required this.child,
      this.remoteFactory});
  @override
  State<AutoSyncHost> createState() => _AutoSyncHostState();
}

class _AutoSyncHostState extends State<AutoSyncHost>
    with WidgetsBindingObserver {
  Timer? timer;
  bool busy = false, active = true;
  int attempts = 0;
  bool scoped(String key) {
    final value = widget.store.data[key];
    return value is Map &&
        widget.store.data['remoteUserId'] != null &&
        value['userId'] == widget.store.data['remoteUserId'] &&
        value['server'] == widget.store.apiBase;
  }

  bool get progressConsent => scoped('autoSyncConsent');
  bool get workspaceConsent => scoped('autoWorkspaceConsent');
  bool get consented => progressConsent || workspaceConsent;
  bool get bidirectional =>
      progressConsent &&
      widget.store.data['autoSyncConsent']['mode'] == 'bidirectional-v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(changed);
    changed();
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.store.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      changed();
    } else {
      timer?.cancel();
    }
  }

  void changed() {
    if (busy || !active || !consented) {
      if (!consented) timer?.cancel();
      return;
    }
    timer?.cancel();
    timer = Timer(const Duration(seconds: 3), upload);
  }

  Future<void> upload() async {
    if (!mounted || busy || !active || !consented) return;
    final remote =
        widget.remoteFactory?.call(widget.store) ?? RemoteSync(widget.store);
    if (remote.progressStatus == 'Sincronizando') {
      timer = Timer(const Duration(seconds: 3), upload);
      return;
    }
    busy = true;
    final owner = widget.store.data['remoteUserId'];
    final server = widget.store.apiBase;
    var progressStage = progressConsent, workspaceStarted = false;
    try {
      final status = bidirectional || workspaceConsent
          ? await remote.request('GET', '/v1/sync/status')
          : null;
      if (status != null && status['userId'] != owner) {
        throw StateError('La respuesta pertenece a otra cuenta.');
      }
      if (!consented) return;
      if (progressConsent && remote.progressStatus != 'Conflicto') {
        await widget.store.setSyncQueue({
          'state': 'pending',
          'userId': owner,
          'server': server,
          'attempt': attempts,
          'updatedAt': DateTime.now().toUtc().toIso8601String()
        });
        if (bidirectional &&
            status != null &&
            widget.store.data['serverProgressVersion'] !=
                status['progressVersion']) {
          await remote.pull();
          await widget.store.acknowledgeProgressVersion(
              status['progressVersion'], owner, server);
        }
        if (progressConsent &&
            remote.progressStatus != 'Conflicto' &&
            remote.progressStatus != 'Sincronizado') {
          await remote.upload();
        }
        await widget.store.setSyncQueue({
          'state':
              remote.progressStatus == 'Conflicto' ? 'conflict' : 'confirmed',
          'userId': owner,
          'server': server,
          'confirmedAt': DateTime.now().toUtc().toIso8601String()
        });
      }
      progressStage = false;
      if (workspaceConsent &&
          widget.store.data['workspaceOutbox']?['state'] != 'conflict') {
        workspaceStarted = true;
        try {
          await widget.store.setWorkspaceQueue(
              {'state': 'pending', 'userId': owner, 'server': server});
          await WorkspaceSynchronizer(widget.store, remote: remote)
              .synchronize(status: status);
          await widget.store.setWorkspaceQueue({
            'state': 'confirmed',
            'userId': owner,
            'server': server,
            'confirmedAt': DateTime.now().toUtc().toIso8601String()
          });
        } catch (error) {
          await widget.store.setWorkspaceQueue({
            'state': error is RemoteSyncFailure && error.status == 409
                ? 'conflict'
                : 'error',
            'userId': owner,
            'server': server
          });
          if (error is! RemoteSyncFailure || error.status != 409) rethrow;
        }
      }
      attempts = 0;
    } catch (error) {
      attempts++;
      if (widget.store.data['remoteUserId'] == owner &&
          widget.store.apiBase == server) {
        try {
          if (!workspaceStarted &&
              workspaceConsent &&
              widget.store.data['workspaceOutbox']?['state'] != 'conflict') {
            await widget.store.setWorkspaceQueue(
                {'state': 'error', 'userId': owner, 'server': server});
          }
          if (progressStage) {
            await widget.store.setSyncQueue({
              'state': error is RemoteSyncFailure && error.status == 409
                  ? 'conflict'
                  : 'error',
              'connection':
                  widget.store.data['syncOutbox']?['connection'] == true,
              'userId': owner,
              'server': server,
              'attempt': attempts,
              'updatedAt': DateTime.now().toUtc().toIso8601String()
            });
          }
        } catch (_) {
          /* Local disk may also be unavailable. Never erase progress. */
        }
      }
    } finally {
      busy = false;
      if (mounted && consented && active) {
        final delay = attempts == 0
            ? 60
            : (30 * (1 << attempts.clamp(0, 5))).clamp(30, 900);
        timer = Timer(Duration(seconds: delay), upload);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
