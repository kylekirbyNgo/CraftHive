import 'package:flutter/material.dart';

/// CraftHive palette (Milestone 1 UI/UX design, section 7.1).
/// Olive moss marks buyer and primary actions; clay marks everything on the seller side.
abstract final class AppColors {
  // Primary greens
  static const moss = Color(0xFF5F6F3E); // primary buttons, active tab, links
  static const deepOlive = Color(0xFF4A5B32); // pressed state, prices
  static const paleSage = Color(0xFFE3E8D3); // soft tints, selected options

  // Seller side
  static const clay = Color(0xFFA9715A); // Sell button, Selling tab, store accents
  static const clayText = Color(0xFF8A5A46); // clay used for text (meets 4.5:1 contrast)
  static const clayTint = Color(0xFFF6ECE7);

  // Accent
  static const softHoney = Color(0xFFE3A93F); // ratings, highlights, avatar ring
  static const amber = Color(0xFFD9A441); // warning, low stock, needs reply
  static const amberText = Color(0xFF8A6514);
  static const amberTint = Color(0xFFFBF3DF);

  // Neutrals
  static const warmCream = Color(0xFFFAF6EE); // app background
  static const lightSand = Color(0xFFF1EADB); // cards, info panels
  static const linen = Color(0xFFE0D6C2); // borders and dividers
  static const darkCocoa = Color(0xFF3B2A20); // main text
  static const grayBrown = Color(0xFF7A6A5E); // secondary text, inactive icons
  static const white = Color(0xFFFFFFFF);

  // Status
  static const fern = Color(0xFF4F7F52); // success: accepted, completed, in stock, verified
  static const fernTint = Color(0xFFE6EFE5);
  static const brick = Color(0xFFB85C4A); // error: sold out, declined, sign-out, unread badges
  static const brickTint = Color(0xFFF7E4E0);
  static const slateTeal = Color(0xFF5B8A8C); // info: notes, shipped, payment sent
  static const tealTint = Color(0xFFEAF1F1);
}
