import SwiftUI

struct MonthPicker: View {
    @Binding var year: Int
    @Binding var month: Int

    private let monthNames = [
        "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
        "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
    ]

    var body: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
            }

            Spacer()

            Text("\(monthNames[month - 1]) \(String(year))")
                .font(.headline)

            Spacer()

            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
            }
        }
        .padding(.horizontal)
    }

    private func goBack() {
        if month == 1 {
            month = 12
            year -= 1
        } else {
            month -= 1
        }
    }

    private func goForward() {
        if month == 12 {
            month = 1
            year += 1
        } else {
            month += 1
        }
    }
}
