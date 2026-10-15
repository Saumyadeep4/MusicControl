import Foundation
import Combine

final class AppStateManager: ObservableObject {
    @Published var isPremium: Int {
        didSet {
            UserDefaults.standard.set(isPremium, forKey: "isPremiumFlag")
        }
    }
    
    init() {
        if UserDefaults.standard.object(forKey: "isPremiumFlag") == nil {
            UserDefaults.standard.set(0, forKey: "isPremiumFlag")
        }
        self.isPremium = UserDefaults.standard.integer(forKey: "isPremiumFlag")
    }
    
    var isLocked: Bool {
        return isPremium == 1
    }
}
