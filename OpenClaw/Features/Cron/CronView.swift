import SwiftUI

struct CronView: View {
    @EnvironmentObject var gateway: GatewayClient
    @State private var jobs: [CronJob] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading jobs...")
                } else if jobs.isEmpty {
                    ContentUnavailableView(
                        "No Cron Jobs",
                        systemImage: "clock",
                        description: Text("Scheduled jobs will appear here.")
                    )
                } else {
                    List {
                        ForEach(jobs) { job in
                            CronJobRow(job: job) {
                                await toggleJob(job)
                            } onRun: {
                                await runJob(job)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Cron Jobs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadJobs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await loadJobs() }
        }
    }

    private func loadJobs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await gateway.sendRequest(
                method: "cron.list",
                params: ["includeDisabled": true]
            )

            guard response.ok,
                  let payload = response.payload?.dict,
                  let jobsArray = payload["jobs"] as? [[String: Any]] else { return }

            jobs = jobsArray.compactMap { dict -> CronJob? in
                guard let id = dict["id"] as? String else { return nil }
                let scheduleDict = dict["schedule"] as? [String: Any]
                let payloadDict = dict["payload"] as? [String: Any]

                return CronJob(
                    id: id,
                    name: dict["name"] as? String,
                    enabled: dict["enabled"] as? Bool ?? true,
                    schedule: CronJob.CronSchedule(
                        kind: scheduleDict?["kind"] as? String,
                        expr: scheduleDict?["expr"] as? String,
                        everyMs: scheduleDict?["everyMs"] as? Int
                    ),
                    payload: CronJob.CronPayload(
                        kind: payloadDict?["kind"] as? String,
                        text: payloadDict?["text"] as? String,
                        message: payloadDict?["message"] as? String
                    )
                )
            }
        } catch {}
    }

    private func toggleJob(_ job: CronJob) async {
        _ = try? await gateway.sendRequest(
            method: "cron.update",
            params: [
                "jobId": job.id,
                "patch": ["enabled": !job.enabled] as [String: Any]
            ]
        )
        await loadJobs()
    }

    private func runJob(_ job: CronJob) async {
        _ = try? await gateway.sendRequest(
            method: "cron.run",
            params: ["jobId": job.id]
        )
    }
}

struct CronJobRow: View {
    let job: CronJob
    let onToggle: () async -> Void
    let onRun: () async -> Void
    @State private var isEnabled: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    Label(job.scheduleDescription, systemImage: "clock")
                    if let kind = job.payload?.kind {
                        Label(kind, systemImage: "bolt.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let text = job.payload?.text ?? job.payload?.message {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    Task { await onRun() }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .onChange(of: isEnabled) {
                        Task { await onToggle() }
                    }
            }
        }
        .padding(.vertical, 4)
        .onAppear { isEnabled = job.enabled }
    }
}
