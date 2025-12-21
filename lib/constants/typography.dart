import 'package:flutter/material.dart';

class AppTypography {
  // Font sizes
  static const double fontSizeXS = 10.0;
  static const double fontSizeS = 12.0;
  static const double fontSizeM = 13.0;
  static const double fontSizeL = 14.0;
  static const double fontSizeXL = 16.0;
  static const double fontSizeXXL = 18.0;
  static const double fontSizeXXXL = 20.0;
  
  // Font weights
  static const FontWeight fontWeightNormal = FontWeight.normal;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightSemiBold = FontWeight.w600;
  static const FontWeight fontWeightBold = FontWeight.bold;
  
  // Text styles
  static const TextStyle headingLarge = TextStyle(
    fontSize: fontSizeXXL,
    fontWeight: fontWeightBold,
  );
  
  static const TextStyle headingMedium = TextStyle(
    fontSize: fontSizeXL,
    fontWeight: fontWeightSemiBold,
  );
  
  static const TextStyle headingSmall = TextStyle(
    fontSize: fontSizeL,
    fontWeight: fontWeightMedium,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontSize: fontSizeL,
    fontWeight: fontWeightNormal,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: fontSizeM,
    fontWeight: fontWeightNormal,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: fontSizeS,
    fontWeight: fontWeightNormal,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: fontSizeXS,
    fontWeight: fontWeightNormal,
  );
  
  static const TextStyle label = TextStyle(
    fontSize: fontSizeM,
    fontWeight: fontWeightMedium,
  );
  
  static const TextStyle tag = TextStyle(
    fontSize: fontSizeS,
    fontWeight: fontWeightMedium,
  );
  
  static const TextStyle button = TextStyle(
    fontSize: fontSizeM,
    fontWeight: fontWeightMedium,
  );
  
  // Helper method to create text style with color
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }
}

