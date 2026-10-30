import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/api_failure.dart';
import '../../../app.dart';
import '../../../cloud_providers.dart';
import '../../../generated/api/api.dart' as api;
import '../../../providers.dart';
import '../../../sync/cloud_data_service.dart';
import '../../../ui/settings/flow_widgets.dart';
import '../../../ui/settings/share_anchor.dart';
import '../../../ui/widgets/wb_widgets.dart';

/// The data rights the API already offers, reachable from the app (F-15): a copy of what the account holds, erasing the
/// cloud data without deleting the account, and removing a registered device. Every action says what it does before it
/// does it, and what it does not touch.
class CloudDataSection extends ConsumerStatefulWidget {
  const CloudDataSection({super.key});

  @override
  ConsumerState<CloudDataSection> createState() => _CloudDataSectionState();
}

class _CloudDataSectionState extends ConsumerState<CloudDataSection> {
  String? _message;
  bool _busy = false;

  void _say(String text) {
    if (mounted) setState(() => _message = text);
  }

  Future<void> _run(Future<void> Function() job,
      {required String failed}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await job();
    } on StaleAccountException {
      // Another account signed in meanwhile: nothing to report about the previous one.
    } on ApiFailure {
      _say(failed);
    } on Exception {
      _say(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
      {required String title,
      required String body,
      required String action}) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => flowDialog(
        context,
        title: title,
        body: body,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _export() => _run(() async {
        final service = ref.read(cloudDataServiceProvider);
        if (service == null) return;
        final bytes = await service.exportDocument();
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path,
            CloudDataService.exportFileName(ref.read(clockProvider)())));
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/json')],
            subject: context.l10n.shareSubject,
            sharePositionOrigin: shareAnchorForContext(context));
      }, failed: context.l10n.cloudExportFailed);

  Future<void> _erase() async {
    final l = context.l10n;
    final confirmed = await _confirm(
        title: l.cloudEraseAction,
        body: l.cloudEraseBody,
        action: l.cloudEraseAction);
    if (!confirmed) return;
    await _run(() async {
      final service = ref.read(cloudDataServiceProvider);
      if (service == null) return;
      await service.eraseCloudData();
      // Switched off only after the server confirmed, and always after it did: with sync on, the next pass would upload the
      // same days again and the erasure would mean nothing.
      await ref.read(cloudSyncProvider).disable();
      _say(l.cloudEraseDone);
    }, failed: l.cloudEraseFailed);
  }

  Future<void> _devices() async {
    final service = ref.read(cloudDataServiceProvider);
    if (service == null) return;
    await _run(() async {
      final list = await service.devices();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => _DevicesSheet(service: service, initial: list),
      );
    }, failed: context.l10n.cloudDevicesFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return WbCard(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.cloudDataTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.cloudDataBody,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                style: flowOutlinedStyle(context),
                onPressed: _busy ? null : _export,
                child: Text(l.cloudExportAction),
              ),
              OutlinedButton(
                style: flowOutlinedStyle(context),
                onPressed: _busy ? null : _devices,
                child: Text(l.cloudDevicesAction),
              ),
              OutlinedButton(
                style: flowOutlinedStyle(context,
                    color: Theme.of(context).colorScheme.error),
                onPressed: _busy ? null : _erase,
                child: Text(l.cloudEraseAction),
              ),
            ]),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(_message!,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DevicesSheet extends StatefulWidget {
  const _DevicesSheet({required this.service, required this.initial});

  final CloudDataService service;
  final List<api.DeviceDto> initial;

  @override
  State<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends State<_DevicesSheet> {
  late List<api.DeviceDto> _devices = List.of(widget.initial);
  String? _message;
  bool _busy = false;

  Future<void> _remove(api.DeviceDto d) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => flowDialog(
        context,
        title: _label(d, l.cloudDeviceUnnamed),
        body: l.cloudDeviceRemoveBody,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.cloudDeviceRemove,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.removeDevice(d.id);
      if (!mounted) return;
      setState(() {
        _devices = [
          for (final x in _devices)
            if (x.id != d.id) x
        ];
        _message = l.cloudDeviceRemoved;
      });
    } on StaleAccountException {
      if (mounted) Navigator.pop(context);
    } on Exception {
      if (mounted) setState(() => _message = l.cloudDeviceRemoveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _label(api.DeviceDto d, String unnamed) {
    final name = (d.model ?? '').trim();
    return '${name.isEmpty ? unnamed : name} (${d.platform.toJson()})';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.cloudDevicesAction,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_devices.isEmpty) Text(l.cloudDevicesEmpty),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in _devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_label(d, l.cloudDeviceUnnamed)),
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _remove(d),
                        child: Text(l.cloudDeviceRemove,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    ),
                ],
              ),
            ),
            if (_message != null)
              Semantics(
                liveRegion: true,
                container: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message!,
                      style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
