class Proposal {
  final String id;
  final String type;
  final String status; // pending|approved|dismissed|snoozed|done|expired
  final String severity; // info|warning|critical
  final String title;
  final String body;
  final String? actionKind;
  final Map<String, dynamic> actionParams;
  final bool requiresClient;
  final bool autoExecuted; // 后端自动执行留痕（evidenceRefs.autoExecuted）

  Proposal({
    required this.id,
    required this.type,
    this.status = 'pending',
    required this.severity,
    required this.title,
    required this.body,
    this.actionKind,
    required this.actionParams,
    required this.requiresClient,
    this.autoExecuted = false,
  });

  factory Proposal.fromJson(Map<String, dynamic> j) => Proposal(
        id: j['id'] as String,
        type: j['type'] as String,
        status: (j['status'] as String?) ?? 'pending',
        severity: (j['severity'] as String?) ?? 'warning',
        title: j['title'] as String,
        body: j['body'] as String,
        actionKind: j['actionKind'] as String?,
        actionParams:
            (j['actionParams'] as Map?)?.cast<String, dynamic>() ?? const {},
        requiresClient: (j['requiresClient'] as bool?) ?? false,
        autoExecuted: (j['autoExecuted'] as bool?) ?? false,
      );
}
