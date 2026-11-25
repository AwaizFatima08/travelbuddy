// Activity: your journeys as passenger and as driver (ActivityScreen.kt).
import 'package:flutter/material.dart';

import '../app/widgets.dart';
import '../core/models.dart';
import '../core/repo.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.me});
  final AppUser me;

  @override
  Widget build(BuildContext context) => MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Activity', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Muted('Your TravelBuddy journeys'),
          const SizedBox(height: 16),
          const Eyebrow('As passenger'),
          const SizedBox(height: 6),
          StreamBuilder<List<RideRequest>>(
            stream: Repo.I.passengerHistory(me.uid),
            builder: (context, s) {
              if (s.hasError) return Muted(Repo.friendly(s.error!));
              if (!s.hasData) return const Loading();
              if (s.data!.isEmpty) return const TbCard(child: Muted('No journeys yet. Join a driver from Home.', center: true));
              return Column(children: [for (final r in s.data!) _row(fmtDate(r.date), 'With ${r.driverName} · ${r.displayPickup}', r.status, r.status == ReqStatus.completed)]);
            },
          ),
          const SizedBox(height: 20),
          const Eyebrow('As driver'),
          const SizedBox(height: 6),
          StreamBuilder<List<Ride>>(
            stream: Repo.I.driverHistory(me.uid),
            builder: (context, s) {
              if (s.hasError) return Muted(Repo.friendly(s.error!));
              if (!s.hasData) return const Loading();
              if (s.data!.isEmpty) return const TbCard(child: Muted('No rides offered yet. Publish your availability from Home.', center: true));
              return Column(children: [
                for (final r in s.data!)
                  _row(fmtDate(r.date), '${r.displayPickup} · ${r.acceptedPassengerIds.length} passenger${r.acceptedPassengerIds.length == 1 ? '' : 's'}${r.status == RideStatus.completed ? ' · ${r.finalPassengerCount} completed' : ''}', r.status, r.status == RideStatus.completed),
              ]);
            },
          ),
        ]),
      );

  Widget _row(String date, String line, String status, bool good) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TbCard(
          child: Row(children: [
            Icon(good ? Icons.check_circle : Icons.circle_outlined, color: good ? successColor : textTertiary),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(date, style: const TextStyle(fontWeight: FontWeight.bold)), Muted(line)])),
            Chip(label: Text(status.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
          ]),
        ),
      );
}
