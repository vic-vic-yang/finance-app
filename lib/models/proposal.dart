class Proposal {
  final String id;
  final String type;
  final String severity; // info|warning|critical
  final String title;
  final String body;
  final String? actionKind;
  final Map<String, dynamic> actionParams;
  final bool requiresClient;

  Proposal({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    this.actionKind,
    required this.actionParams,
    required this.requiresClient,
  });

  factory Proposal.fromJson(Map<String, dynamic> j) => Proposal(
        id: j['id'] as String,
        type: j['type'] as String,
        severity: (j['severity'] as String?) ?? 'warning',
        title: j['title'] as String,
        body: j['body'] as String,
        actionKind: j['actionKind'] as String?,
        actionParams:
            (j['actionParams'] as Map?)?.cast<String, dynamic>() ?? const {},
        requiresClient: (j['requiresClient'] as bool?) ?? false,
      );
}
