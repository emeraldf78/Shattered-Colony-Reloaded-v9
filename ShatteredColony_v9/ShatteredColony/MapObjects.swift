import Foundation
import SpriteKit

// MARK: - Debris Type
enum DebrisType: CaseIterable {
    case car
    case dumpster
    case recycling
    case cardboardBox
    
    var emoji: String {
        switch self {
        case .car:          return "🚗"
        case .dumpster:     return "🗑️"
        case .recycling:    return "♻️"
        case .cardboardBox: return "📦"
        }
    }
    
    var isTraversable: Bool {
        switch self {
        case .car, .dumpster:
            return false
        case .recycling, .cardboardBox:
            return true
        }
    }
    
    var displayName: String {
        switch self {
        case .car:          return "Car"
        case .dumpster:     return "Dumpster"
        case .recycling:    return "Recycling Bin"
        case .cardboardBox: return "Cardboard Box"
        }
    }
    
    // Resource ranges
    var survivorRange: ClosedRange<Int> {
        switch self {
        case .car:          return 0...4
        case .dumpster:     return 0...2
        case .recycling:    return 0...0
        case .cardboardBox: return 0...0
        }
    }
    
    var woodRange: ClosedRange<Int> {
        switch self {
        case .car:          return 30...50
        case .dumpster:     return 20...40
        case .recycling:    return 10...30
        case .cardboardBox: return 0...20
        }
    }
    
    var bulletRange: ClosedRange<Int> {
        switch self {
        case .car:          return 30...50
        case .dumpster:     return 20...40
        case .recycling:    return 10...30
        case .cardboardBox: return 0...20
        }
    }
    
    func generateResources() -> Resources {
        return Resources(
            wood: Int.random(in: woodRange),
            bullets: Int.random(in: bulletRange),
            survivors: Int.random(in: survivorRange)
        )
    }
    
    var color: SKColor {
        switch self {
        case .car:          return SKColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)
        case .dumpster:     return SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0)
        case .recycling:    return SKColor(red: 0.2, green: 0.4, blue: 0.5, alpha: 1.0)
        case .cardboardBox: return SKColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1.0)
        }
    }
}

// MARK: - Debris Object
class DebrisObject {
    let id: Int
    let position: GridPosition
    let debrisType: DebrisType
    var resources: Resources
    var hasWorkshop: Bool = false
    weak var node: SKNode?
    
    init(id: Int, position: GridPosition, type: DebrisType) {
        self.id = id
        self.position = position
        self.debrisType = type
        self.resources = type.generateResources()
    }
    
    init(id: Int, position: GridPosition, type: DebrisType, resources: Resources) {
        self.id = id
        self.position = position
        self.debrisType = type
        self.resources = resources
    }
    
    var isTraversable: Bool {
        return debrisType.isTraversable
    }
    
    var hasResources: Bool {
        return resources.wood > 0 || resources.bullets > 0 || resources.survivors > 0
    }
    
    var isEmpty: Bool {
        return !hasResources
    }
    
    func createNode() -> SKNode {
        let size = CGSize(width: GridConfig.tileSize - 2, height: GridConfig.tileSize - 2)
        let node = SKShapeNode(rectOf: size, cornerRadius: 2)
        node.fillColor = debrisType.color
        node.strokeColor = isTraversable ? .clear : SKColor(white: 0.2, alpha: 1.0)
        node.lineWidth = 1
        node.position = position.toScenePosition()
        node.zPosition = ZPosition.droppedResources
        
        // Add emoji
        let emoji = SKLabelNode(fontNamed: "Apple Color Emoji")
        emoji.text = debrisType.emoji
        emoji.fontSize = 10
        emoji.verticalAlignmentMode = .center
        emoji.horizontalAlignmentMode = .center
        node.addChild(emoji)
        
        self.node = node
        return node
    }
    
    func updateVisual() {
        guard let shapeNode = node as? SKShapeNode else { return }
        
        // Fade out as resources deplete
        if isEmpty {
            shapeNode.alpha = 0.3
        } else {
            shapeNode.alpha = 1.0
        }
    }
}

// MARK: - Map Object Manager Extension
extension GameMap {
    // These will be added to GameMap
}
