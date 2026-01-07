import Foundation

protocol ShortcutHandler {
    func register()
    func unregister()
    var key: String { get set }
    var modifiers: UInt32 { get set }
    var description: String { get }
    var shortcutID: UInt32? { get set }
} 