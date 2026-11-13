import 'package:flutter/material.dart';

class CarShareTextField extends StatelessWidget {
  const CarShareTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.minLines,
    this.maxLines = 1,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final int? minLines;
  final int? maxLines;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboardType,
    obscureText: obscureText,
    textInputAction: textInputAction,
    minLines: minLines,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hintText,
      alignLabelWithHint: maxLines != 1,
      // A tall field keeps its icon at the first line, not floating in the middle.
      prefixIcon: maxLines == 1
          ? Icon(icon)
          : Align(
              alignment: Alignment.topCenter,
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Icon(icon),
              ),
            ),
    ),
  );
}
