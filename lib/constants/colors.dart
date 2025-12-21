import 'package:flutter/material.dart';

class AppColors {
  // Primary colors
  static const Color primary = Color(0xFF191921);
  static const Color secondary = Color(0xFFACAFBF);

  // Background colors
  static const Color background = Color(0xFF191921);
  static const Color scaffoldBackground = Color(0xFF191921);
  static const Color photoGridBackground = Colors.white;

  // Text colors
  static const Color textPrimary = Color(0xFF191921);
  static const Color textSecondary = Color(0xFFACAFBF);
  static const Color textWhite = Colors.white;
  static const Color textWhite70 = Colors.white70;
  static const Color textGrey = Colors.grey;

  // Tag colors
  static const Color tagActiveBackground = Colors.white;
  static const Color tagInactiveBorder = Color(0xFFACAFBF);
  static const Color tagInactiveBorderOpacity = Color(0x77ACAFBF);

  // Snackbar colors
  static const Color snackbarBackground = AppColors.primary;
  static const Color snackbarText = AppColors.selectionWhite;

  // Selection colors
  static const Color selectionBlue = Colors.blue;
  static const Color selectionWhite = Colors.white;

  // Border colors
  static const Color borderGrey = Colors.grey;

  // Shadow colors
  static const Color shadowBlack = Colors.black;

  // Helper methods for opacity
  static Color secondaryWithOpacity(double opacity) {
    return secondary.withValues(alpha: opacity);
  }

  static Color tagInactiveBorderWithOpacity(double opacity) {
    return tagInactiveBorder.withValues(alpha: opacity);
  }

  static Color whiteWithOpacity(double opacity) {
    return Colors.white.withValues(alpha: opacity);
  }

  static Color blackWithOpacity(double opacity) {
    return Colors.black.withValues(alpha: opacity);
  }
}
