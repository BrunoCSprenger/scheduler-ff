class GroupSummary {
  const GroupSummary({
    required this.inviteCode,
    required this.name,
    required this.memberCount,
    required this.role,
    this.meetingStart,
    this.meetingDurationMinutes,
  });

  final String inviteCode;
  final String name;
  final int memberCount;
  final String role;
  final DateTime? meetingStart;
  final int? meetingDurationMinutes;
}
