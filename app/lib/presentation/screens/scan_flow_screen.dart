import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../application/device_manager.dart';
import '../../application/scan_orchestrator.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

enum _FlowPhase { initializingCamera, cameraError, ready, analyzing, analysisFailed }

class ScanFlowScreen extends ConsumerStatefulWidget {
  const ScanFlowScreen({super.key, required this.crop});
  final String crop;

  @override
  ConsumerState<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends ConsumerState<ScanFlowScreen> {
  CameraController? _controller;
  _FlowPhase _phase = _FlowPhase.initializingCamera;
  String? _errorMessage;
  AnalysisStage? _analysisStage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _phase = _FlowPhase.cameraError;
          _errorMessage = 'No camera was found on this device.';
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _phase = _FlowPhase.ready;
      });
    } catch (e) {
      setState(() {
        _phase = _FlowPhase.cameraError;
        _errorMessage = 'Could not start the camera: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _phase = _FlowPhase.analyzing);

    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() {
          _phase = _FlowPhase.analysisFailed;
          _errorMessage = 'Could not read the captured image. Please try again.';
        });
        return;
      }

      final orchestrator = ref.read(scanOrchestratorProvider);
      final nirDevice = ref.read(deviceManagerProvider.notifier).device;

      final result = await orchestrator.analyze(
        image: decoded,
        crop: widget.crop,
        nirDevice: nirDevice,
        cameraMetadata: {
          'resolution': '${decoded.width}x${decoded.height}',
          'lens_direction': controller.description.lensDirection.name,
        },
        onProgress: (stage) {
          if (mounted) setState(() => _analysisStage = stage);
        },
      );

      if (!mounted) return;

      result.when(
        ok: (scan) async {
          await ref.read(scanRepositoryProvider).save(scan);
          if (!mounted) return;
          context.pushReplacement('/scan/result/${scan.scanId}');
        },
        err: (message, _) {
          setState(() {
            _phase = _FlowPhase.analysisFailed;
            _errorMessage = message;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _FlowPhase.analysisFailed;
        _errorMessage = 'Unexpected error during capture: $e';
      });
    }
  }

  void _retake() {
    setState(() {
      _phase = _FlowPhase.ready;
      _errorMessage = null;
      _analysisStage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Capture · ${widget.crop}'),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _FlowPhase.initializingCamera => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          _FlowPhase.cameraError => _MessagePanel(
              icon: Icons.videocam_off_outlined,
              message: _errorMessage ?? 'Camera unavailable.',
              actionLabel: 'Back',
              onAction: () => context.pop(),
            ),
          _FlowPhase.ready => _CaptureView(controller: _controller!, onCapture: _capture),
          _FlowPhase.analyzing => _AnalyzingView(stage: _analysisStage),
          _FlowPhase.analysisFailed => _MessagePanel(
              icon: Icons.error_outline,
              message: _errorMessage ?? 'Analysis failed.',
              actionLabel: 'Retake',
              onAction: _retake,
            ),
        },
      ),
    );
  }
}

class _CaptureView extends StatelessWidget {
  const _CaptureView({required this.controller, required this.onCapture});
  final CameraController controller;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(controller)),
        // Framing guide (§8): a simple rectangle guide for where to place
        // the seed batch, not a real detection overlay.
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              heightFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Text(
              'Place 10–50 seeds inside the guide.\n'
              'Avoid overlapping seeds, strong shadows, glare, blur, and clutter.',
              style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.xxl,
          child: Center(
            child: GestureDetector(
              onTap: onCapture,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 4),
                ),
                child: const Icon(Icons.circle, color: Colors.black87, size: 56),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView({required this.stage});
  final AnalysisStage? stage;

  String get _label => switch (stage) {
        AnalysisStage.checkingQuality => 'Checking image quality…',
        AnalysisStage.detectingSeeds => 'Detecting and segmenting seeds…',
        AnalysisStage.extractingFeatures => 'Extracting visual features…',
        AnalysisStage.classifying => 'Scoring each seed…',
        AnalysisStage.readingNir => 'Reading NIR sensor…',
        AnalysisStage.fusing => 'Combining sensor evidence…',
        AnalysisStage.saving => 'Saving scan…',
        AnalysisStage.done || null => 'Preparing results…',
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: AppSpacing.lg),
          Text(_label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
