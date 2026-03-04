import Foundation

struct Account: Codable, Identifiable {
    let id: String
    let name: String
    let bank: String
    let color: String
}
