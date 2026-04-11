import Foundation

protocol PreferencesServiceProtocol {
    var selectedModel: String? { get set }
}

final class PreferencesService: PreferencesServiceProtocol {
    private let defaults: UserDefaults
    private let key = "selected_model"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedModel: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
