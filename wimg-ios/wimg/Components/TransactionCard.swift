import SwiftUI

struct TransactionCard: View {
    let transaction: Transaction
    var onTap: (() -> Void)?

    private var category: WimgCategory {
        WimgCategory.from(transaction.category)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 14) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: category.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(category.color)
                }

                // Description + category
                VStack(alignment: .leading, spacing: 3) {
                    Text(transaction.description)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(WimgTheme.text)

                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(WimgTheme.textSecondary)
                }

                Spacer()

                // Amount
                Text(formatAmount(transaction.amount))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(transaction.isIncome ? .green : WimgTheme.text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

func formatAmount(_ amount: Double) -> String {
    let formatted = String(format: "%.2f", abs(amount))
    let sign = amount < 0 ? "-" : (amount > 0 ? "+" : "")
    return "\(sign)\(formatted) \u{20AC}"
}

func formatAmountShort(_ amount: Double) -> String {
    String(format: "%.2f \u{20AC}", amount)
}
