import 'package:flutter/material.dart';
import 'constants/colors.dart';
import 'constants/strings.dart';

class DialogHelpers {
  /// Builds a standard text field decoration for dark theme dialogs
  static InputDecoration buildTextFieldDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: AppColors.whiteWithOpacity(0.5)),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.whiteWithOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.whiteWithOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.secondary),
      ),
    );
  }

  /// Builds a standard cancel button for dialogs
  static Widget buildCancelButton(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.whiteWithOpacity(0.7),
      ),
      child: const Text(AppStrings.cancel),
    );
  }

  /// Shows a delete confirmation dialog
  static Future<bool?> showDeleteConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primary,
        title: const Text(
          AppStrings.delete,
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          AppStrings.deleteTagConfirm,
          style: TextStyle(color: AppColors.textWhite),
        ),
        actions: [
          buildCancelButton(context),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
  }

  /// Builds a delete button widget for edit tag dialog
  static Widget buildDeleteTagButton(
    BuildContext context,
    VoidCallback onDelete,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () async {
          final confirm = await showDeleteConfirmationDialog(context);
          if (confirm == true && context.mounted) {
            onDelete();
          }
        },
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: const Text(
          AppStrings.delete,
          style: TextStyle(color: Colors.red),
        ),
      ),
    );
  }
}
