import SwiftUI

struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fbType = "feedback"
    @State private var fbMessage = ""
    @State private var fbSending = false
    @State private var fbResult: (number: Int, url: String)?
    @State private var fbError = ""
    @State private var history: [FeedbackEntry] = []

    struct FeedbackEntry: Codable, Identifiable {
        var id: Int { number }
        let number: Int
        let url: String
        let type: String
        let message: String
        let date: String
    }

    private static let historyKey = "wimg_feedback_history"

    private static func loadHistory() -> [FeedbackEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let entries = try? JSONDecoder().decode([FeedbackEntry].self, from: data) else { return [] }
        return entries
    }

    private static func saveEntry(_ entry: FeedbackEntry) {
        var history = loadHistory()
        history.insert(entry, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private let types: [(value: String, label: String, icon: String)] = [
        ("bug", "Bug", "\u{1F41B}"),
        ("feature", "Wunsch", "\u{2728}"),
        ("feedback", "Feedback", "\u{1F4AC}"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let result = fbResult {
                        // Success
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Danke!")
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .foregroundStyle(WimgTheme.text)
                                Text("Issue #\(result.number) wurde erstellt.")
                                    .font(.subheadline)
                                    .foregroundStyle(WimgTheme.textSecondary)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        // Type picker
                        HStack(spacing: 8) {
                            ForEach(types, id: \.value) { t in
                                Button {
                                    fbType = t.value
                                } label: {
                                    Text("\(t.icon) \(t.label)")
                                        .font(.system(.caption, design: .rounded, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(fbType == t.value ? Color.indigo.opacity(0.15) : Color(.systemGray6))
                                        .foregroundStyle(fbType == t.value ? .indigo : WimgTheme.textSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Message
                        TextField("Beschreibe dein Feedback...", text: $fbMessage, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(3...8)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if !fbError.isEmpty {
                            Text(fbError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        // Submit
                        Button {
                            Task { await submitFeedback() }
                        } label: {
                            Text(fbSending ? "Sende..." : "Feedback senden")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(WimgTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(fbSending || fbMessage.trimmingCharacters(in: .whitespaces).count < 3)
                        .opacity(fbMessage.trimmingCharacters(in: .whitespaces).count < 3 ? 0.4 : 1)

                        Text("Erstellt ein GitHub Issue — kein Account nötig")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(WimgTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    // History
                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Deine Feedbacks")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(WimgTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            ForEach(history.prefix(5)) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.type == "bug" ? "\u{1F41B}" : entry.type == "feature" ? "\u{2728}" : "\u{1F4AC}")
                                        .font(.subheadline)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.message)
                                            .font(.system(.caption, design: .rounded, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundStyle(WimgTheme.text)
                                        Text("#\(entry.number) · \(entry.date)")
                                            .font(.system(size: 10, design: .rounded))
                                            .foregroundStyle(WimgTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                        .foregroundStyle(WimgTheme.textSecondary)
                                }
                                .padding(10)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(20)
            }
            .background(WimgTheme.bg)
            .onAppear { history = Self.loadHistory() }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private func submitFeedback() async {
        let msg = fbMessage.trimmingCharacters(in: .whitespaces)
        guard msg.count >= 3 else { return }
        fbSending = true
        fbError = ""

        do {
            let payload: [String: String] = ["type": fbType, "message": msg, "platform": "ios"]
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            var request = URLRequest(url: URL(string: "\(WimgConfig.syncBaseURL)/feedback")!)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let number = json["number"] as? Int,
               let url = json["url"] as? String {
                let entry = FeedbackEntry(
                    number: number, url: url, type: fbType,
                    message: msg,
                    date: {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        return f.string(from: Date())
                    }()
                )
                Self.saveEntry(entry)
                await MainActor.run {
                    fbResult = (number: number, url: url)
                    fbMessage = ""
                    history = Self.loadHistory()
                }
            }
        } catch {
            await MainActor.run {
                fbError = "Feedback konnte nicht gesendet werden"
            }
        }

        await MainActor.run { fbSending = false }
    }
}
