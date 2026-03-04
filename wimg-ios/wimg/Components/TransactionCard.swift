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
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(category.color)
                }

                // Description + category
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Amount
                Text(formatAmount(transaction.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(transaction.isIncome ? .green : .primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

func formatAmount(_ amount: Double) -> String {
    let formatted = String(format: "%.2f", abs(amount))
    let sign = amount < 0 ? "-" : (amount > 0 ? "+" : "")
    return "\(sign)\(formatted) €"
}

func formatAmountShort(_ amount: Double) -> String {
    String(format: "%.2f €", amount)
}
