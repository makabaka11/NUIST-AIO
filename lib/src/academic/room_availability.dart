enum RoomUse { free, busy, partial, unknown }

class RoomPeriod {
  RoomPeriod.fromJson(Map<String, dynamic> data)
    : period = (data['period'] as num).toInt(),
      state = switch (data['state']) {
        'free' => RoomUse.free,
        'busy' => RoomUse.busy,
        _ => RoomUse.unknown,
      },
      types = (data['types'] as List? ?? []).map((x) => '$x').toList();
  final int period;
  final RoomUse state;
  final List<String> types;
}

class RoomSlot {
  RoomSlot.fromJson(Map<String, dynamic> data)
    : start = (data['start'] as num).toInt(),
      end = (data['end'] as num).toInt(),
      label = '${data['label']}',
      from = '${data['from'] ?? ''}',
      to = '${data['to'] ?? ''}';
  final int start, end;
  final String label, from, to;
}

class RoomAvailability {
  RoomAvailability.fromJson(Map<String, dynamic> data)
    : name = '${data['name'] ?? ''}',
      type = '${data['type'] ?? ''}',
      seats = data['seats'] as num?,
      periods = (data['periods'] as List)
          .map((x) => RoomPeriod.fromJson(Map<String, dynamic>.from(x)))
          .toList();
  final String name, type;
  final num? seats;
  final List<RoomPeriod> periods;
  List<RoomPeriod> during(RoomSlot slot) => periods
      .where((p) => p.period >= slot.start && p.period <= slot.end)
      .toList();
  RoomUse stateFor(RoomSlot slot) {
    final values = during(slot);
    if (values.length != slot.end - slot.start + 1 ||
        values.any((p) => p.state == RoomUse.unknown)) {
      return RoomUse.unknown;
    }
    if (values.every((p) => p.state == RoomUse.free)) return RoomUse.free;
    if (values.every((p) => p.state == RoomUse.busy)) return RoomUse.busy;
    return RoomUse.partial;
  }
}
