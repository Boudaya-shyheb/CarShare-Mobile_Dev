import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

Widget adminSectionHeader(BuildContext context, String title, String subtitle, IconData icon) =>
    Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF059669)]),
        boxShadow: [BoxShadow(color: carShareGreen.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Row(children: [
        CircleAvatar(backgroundColor: Colors.white.withValues(alpha: .18), child: Icon(icon, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        IconButton(onPressed: () => AuthService.instance.signOut(), tooltip: 'Sign out',
          style: IconButton.styleFrom(foregroundColor: Colors.white), icon: const Icon(Icons.logout)),
      ]),
    );
