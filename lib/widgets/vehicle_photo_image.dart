import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/vehicle_service.dart';

class VehiclePhotoImage extends StatefulWidget {
  const VehiclePhotoImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<VehiclePhotoImage> createState() => _VehiclePhotoImageState();
}

class _VehiclePhotoImageState extends State<VehiclePhotoImage> {
  late Future<Uint8List> _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant VehiclePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _loadPhoto();
  }

  void _loadPhoto() {
    _photo = VehicleService.instance.getPhotoBytes(widget.url);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: widget.borderRadius ?? BorderRadius.zero,
    child: FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
          );
        }
        if (snapshot.hasError) {
          return _placeholder(Icons.broken_image_outlined);
        }
        return _placeholder(Icons.directions_car_outlined, loading: true);
      },
    ),
  );

  Widget _placeholder(IconData icon, {bool loading = false}) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ColoredBox(
      color: const Color(0xFFF1F5F4),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: const Color(0xFF718096), size: 32),
      ),
    ),
  );
}
