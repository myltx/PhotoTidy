enum LargeFileCountOption: CaseIterable, Hashable {
    case ten, twenty, fifty, hundred
    
    var title: String {
        switch self {
        case .ten: return "10"
        case .twenty: return "20"
        case .fifty: return "50"
        case .hundred: return "100"
        }
    }
    
    var displayText: String { title }
    
    var limit: Int {
        switch self {
        case .ten: return 10
        case .twenty: return 20
        case .fifty: return 50
        case .hundred: return 100
        }
    }
}
