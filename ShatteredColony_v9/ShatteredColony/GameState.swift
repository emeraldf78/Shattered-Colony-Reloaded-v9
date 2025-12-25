import Foundation
import SpriteKit

// MARK: - Game State
class GameState {
    static var shared: GameState!
    
    let map: GameMap
    
    // Time control
    var timeSpeed: TimeSpeed = .normal
    var roundTimer: TimeInterval
    var gameTime: TimeInterval = 0
    var isGameOver: Bool = false
    var isVictory: Bool = false
    
        //Checking for established base
        var hasEstablishedBase: Bool = false

    // Units
    var zombies: [Zombie] = []
    var trucks: [Truck] = []
    var freeSurvivors: [FreeSurvivor] = []
    
    // Buildings
    var depots: [Depot] = []
    var workshops: [Workshop] = []
    var sniperTowers: [SniperTower] = []
    var barricades: [Barricade] = []
    
    var allPlayerBuildings: [PlayerBuilding] {
        return depots + workshops + sniperTowers + barricades
    }
    
    // Dropped resources
    var droppedResources: [DroppedResource] = []
    
    // Tents (lost survivor camps)
    var tents: [Tent] = []
    
    weak var scene: GameScene?
    
    init(map: GameMap) {
        self.map = map
        self.roundTimer = GameBalance.roundDuration
        GameState.shared = self
    }
    
    // MARK: - Update Loop
    
    func update(deltaTime: TimeInterval) {
        guard timeSpeed != .paused && !isGameOver else { return }
        
        let scaledDelta = deltaTime * Double(timeSpeed.rawValue)
        gameTime += scaledDelta
        
        // Update round timer
        updateRoundTimer(deltaTime: scaledDelta)
        
        // Update all units
        for zombie in zombies where !zombie.isDead {
            zombie.update(deltaTime: scaledDelta, gameState: self)
        }
        
        for truck in trucks {
            truck.update(deltaTime: scaledDelta, gameState: self)
        }
        
        for survivor in freeSurvivors {
            survivor.update(deltaTime: scaledDelta, gameState: self)
        }
        
        // Update buildings
        for workshop in workshops {
            workshop.update(deltaTime: scaledDelta, gameState: self)
        }
        
        for sniper in sniperTowers {
            sniper.update(deltaTime: scaledDelta, gameState: self)
        }
        
        // Update tents (noise generation)
        updateTents(deltaTime: scaledDelta)
        

        // Check game over
        checkGameOver()
    }
    
    // MARK: - Round Timer
    
    private func updateRoundTimer(deltaTime: TimeInterval) {
        roundTimer -= deltaTime
        
        if roundTimer <= 0 {
            // Spawn bridge zombies
            spawnBridgeZombies()
            
            // Reset timer
            roundTimer = GameBalance.roundDuration
        }
    }
    
    private func spawnBridgeZombies() {
        guard let bridge = map.getRandomFunctionalBridge() else { return }
        guard let spawnTile = bridge.tiles.first else { return }
        
        // Find nearest depot
        let nearestDepot = findNearestDepot(to: spawnTile)
        
        for i in 0..<GameBalance.bridgeZombieSpawnCount {
            // Offset spawn positions slightly
            let offsetX = i % 3 - 1
            let offsetY = i / 3 - 1
            let spawnPos = GridPosition(x: spawnTile.x + offsetX, y: spawnTile.y + offsetY)
            
            let zombie = Zombie(at: spawnPos, type: .bridge)
            zombie.targetDepot = nearestDepot
            
            if let depot = nearestDepot {
                _ = zombie.setDestination(depot.gridPosition, map: map)
            }
            
            zombies.append(zombie)
            
            if let scene = scene {
                let node = zombie.createNode()
                scene.gameLayer.addChild(node)
            }
        }
    }
    
    // MARK: - Noise System
    
    func createNoiseEvent(at position: GridPosition, level: NoiseLevel) {
        let radius: Int
        switch level {
        case .high:
            radius = GameBalance.shootingNoiseRadius
        case .medium:
            radius = GameBalance.workshopNoiseRadius
        case .low:
            radius = GameBalance.movementNoiseRadius
        case .none:
            return
        }
        
        // Check city buildings for zombie spawns
        let nearbyBuildings = map.getCityBuildingsInRadius(of: position, radius: radius)
        
        for building in nearbyBuildings where building.hasZombies {
            let roll = CGFloat.random(in: 0...1)
            if roll <= level.triggerChance {
                if building.depositZombie() {
                    spawnZombieFromBuilding(building, noiseSource: position, noiseLevel: level)
                }
            }
        }
        
        // Alert existing zombies
        for zombie in zombies where !zombie.isDead {
            let distance = zombie.gridPosition.distance(to: position)
            if distance <= radius {
                zombie.respondToNoise(level: level, source: position, gameState: self)
            }
        }
    }
    
    private func spawnZombieFromBuilding(_ building: CityBuilding, noiseSource: GridPosition, noiseLevel: NoiseLevel) {
        let zombie = Zombie(at: building.doorPosition, type: .normal)
        zombie.respondToNoise(level: noiseLevel, source: noiseSource, gameState: self)
        
        zombies.append(zombie)
        
        if let scene = scene {
            let node = zombie.createNode()
            scene.gameLayer.addChild(node)
        }
    }
    
    // MARK: - Zombie Management
    
    func spawnZombie(at position: GridPosition, type: ZombieType) {
        let zombie = Zombie(at: position, type: type)
        zombies.append(zombie)
        
        if let scene = scene {
            let node = zombie.createNode()
            scene.gameLayer.addChild(node)
        }
    }
    
    func killZombie(_ zombie: Zombie) {
        zombie.isDead = true
        zombie.node?.removeFromParent()
        zombies.removeAll { $0 === zombie }
    }
    
    // MARK: - Truck Management
    
    func addTruck(_ truck: Truck) {
        trucks.append(truck)
        
        if let scene = scene {
            let node = truck.createNode()
            scene.gameLayer.addChild(node)
        }
    }
    
    func removeTruck(_ truck: Truck) {
        truck.node?.removeFromParent()
        trucks.removeAll { $0 === truck }
    }
    
    // MARK: - Free Survivor Management
    
    func addFreeSurvivor(_ survivor: FreeSurvivor) {
        freeSurvivors.append(survivor)
        
        if let scene = scene {
            let node = survivor.createNode()
            scene.gameLayer.addChild(node)
        }
    }
    
    func removeFreeSurvivor(_ survivor: FreeSurvivor) {
        survivor.node?.removeFromParent()
        freeSurvivors.removeAll { $0 === survivor }
    }
    
    // MARK: - Building Management
    
func addDepot(_ depot: Depot, at position: GridPosition) -> Bool {
        guard map.canPlacePlayerBuilding(type: .depot, at: position, depots: depots) else {
            return false
        }
        
        // Filter for functional depots
        let activeDepots = depots.filter { !$0.isDestroyed }
        
        // --- The 8-Block Rule ---
        // Only enforce this if an active base already exists.
        if !activeDepots.isEmpty {
            let isConnected = activeDepots.contains { existing in
                return position.distance(to: existing.gridPosition) <= 8
            }
            if !isConnected {
                print("Too far from existing network!")
                return false
            }
        }

        if map.placePlayerBuilding(depot, at: position) {
            depots.append(depot)
            // Immediately mark base as established so Game Over logic starts monitoring
            hasEstablishedBase = true
            
            // Create visual node
            if let scene = scene {
                let node = depot.createNode()
                scene.gameLayer.addChild(node)
            }
            
            // Update any bridge zombies that were waiting for a depot
            updateBridgeZombieTargets()
            
            return true
        }
        return false
    }
    
    func updateBridgeZombieTargets() {
        // Find bridge zombies without targets and assign them to nearest depot
        for zombie in zombies where zombie.zombieType == .bridge && zombie.targetDepot == nil {
            if let nearestDepot = findNearestDepot(to: zombie.gridPosition) {
                zombie.targetDepot = nearestDepot
                _ = zombie.setDestination(nearestDepot.gridPosition, map: map)
            }
        }
    }
    
    func addWorkshop(_ workshop: Workshop, at position: GridPosition, targetBuilding: CityBuilding?) -> Bool {
        guard map.canPlacePlayerBuilding(type: .workshop, at: position, depots: depots) else {
            return false
        }
        
        // Find source depot
        guard let sourceDepot = findNearestDepot(to: position) else { return false }
        
        workshop.sourceDepot = sourceDepot
        workshop.targetBuilding = targetBuilding
        
        _ = map.placePlayerBuilding(workshop, at: position)
        workshops.append(workshop)
        
        if let scene = scene {
            let node = workshop.createNode()
            scene.gameLayer.addChild(node)
        }
        
        return true
    }
    
    func addSniperTower(_ sniper: SniperTower, at position: GridPosition) -> Bool {
        guard map.canPlacePlayerBuilding(type: .sniperTower, at: position, depots: depots) else {
            return false
        }
        
        guard let sourceDepot = findNearestDepot(to: position) else { return false }
        sniper.sourceDepot = sourceDepot
        
        _ = map.placePlayerBuilding(sniper, at: position)
        sniperTowers.append(sniper)
        
        if let scene = scene {
            let node = sniper.createNode()
            scene.gameLayer.addChild(node)
        }
        
        return true
    }
    
    func addBarricade(_ barricade: Barricade, at position: GridPosition) -> Bool {
        guard map.canPlacePlayerBuilding(type: .barricade, at: position, depots: depots) else {
            return false
        }
        
        guard let sourceDepot = findNearestDepot(to: position) else { return false }
        barricade.sourceDepot = sourceDepot
        
        _ = map.placePlayerBuilding(barricade, at: position)
        barricades.append(barricade)
        
        if let scene = scene {
            let node = barricade.createNode()
            scene.gameLayer.addChild(node)
        }
        
        return true
    }
    
    func removeWorkshop(_ workshop: Workshop) {
        workshop.node?.removeFromParent()
        map.removePlayerBuilding(workshop)
        workshops.removeAll { $0 === workshop }
    }
    
    func destroyPlayerBuilding(_ building: PlayerBuilding) {
        building.node?.removeFromParent()
        map.removePlayerBuilding(building)
        
        if let depot = building as? Depot {
            depots.removeAll { $0 === depot }
        } else if let workshop = building as? Workshop {
            workshops.removeAll { $0 === workshop }
        } else if let sniper = building as? SniperTower {
            sniperTowers.removeAll { $0 === sniper }
        } else if let barricade = building as? Barricade {
            barricades.removeAll { $0 === barricade }
        }
    }
    
    // MARK: - Dropped Resources
    
    func addDroppedResource(_ resource: DroppedResource) {
        droppedResources.append(resource)
        
        if let scene = scene {
            let node = SKShapeNode(rectOf: CGSize(width: 8, height: 8))
            node.fillColor = .orange
            node.strokeColor = .yellow
            node.position = resource.position.toScenePosition()
            node.zPosition = ZPosition.droppedResources
            resource.node = node
            scene.gameLayer.addChild(node)
        }
    }
    
    // MARK: - Tent Management
    
    func addTent(_ tent: Tent) {
        tents.append(tent)
        
        if let scene = scene {
            let node = SKShapeNode(rectOf: CGSize(width: GridConfig.tileSize - 2, height: GridConfig.tileSize - 2))
            node.fillColor = TileType.tent.color
            node.strokeColor = SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0)
            node.lineWidth = 1
            node.position = tent.position.toScenePosition()
            node.zPosition = ZPosition.droppedResources
            
            // Add tent icon
            let icon = SKLabelNode(fontNamed: "Apple Color Emoji")
            icon.text = "⛺️"
            icon.fontSize = 10
            icon.verticalAlignmentMode = .center
            node.addChild(icon)
            
            tent.node = node
            scene.gameLayer.addChild(node)
            scene.refreshTerrain()
        }
    }
    
    func removeTent(_ tent: Tent) {
        tent.node?.removeFromParent()
        map.removeTent(tent)
        tents.removeAll { $0 === tent }
        scene?.refreshTerrain()
    }
    
    func destroyTent(_ tent: Tent) {
        // Handle units routing to this tent
        notifyTentDestroyed(tent)
        
        // Convert survivors to zombies, drop resources
        tent.onDestroyed(gameState: self)
        
        // Remove the tent
        removeTent(tent)
    }
    
    func notifyTentDestroyed(_ tent: Tent) {
        // Check trucks routing to tent (if any were somehow targeting it)
        // and survivors that might have been heading to tent location
        // Apply lost survivor rules: 50% find depot, 50% make new tent
        
        // For now, tents don't have units routing TO them directly
        // But if we add that feature, handle it here
    }
    
    func getTent(at position: GridPosition) -> Tent? {
        return tents.first { $0.position == position }
    }
    
    func updateTents(deltaTime: TimeInterval) {
        for tent in tents {
            tent.update(deltaTime: deltaTime, gameState: self)
        }
    }
    
    // MARK: - Helper Methods
    
    func findNearestDepot(to position: GridPosition, excluding: Depot? = nil) -> Depot? {
        var nearest: Depot?
        var nearestDistance = Int.max
        
        for depot in depots where !depot.isDestroyed && depot !== excluding {
            let distance = position.distance(to: depot.gridPosition)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = depot
            }
        }
        
        return nearest
    }
    
    func isWithinAnyDepotRadius(_ position: GridPosition) -> Bool {
        return depots.contains { depot in
            position.isWithinRadius(GameBalance.depotBuildRadius, of: depot.gridPosition)
        }
    }
    
    // MARK: - Game Over
    
private func checkGameOver() {
        // 1. Monitor for the "First Depot" placement
        // Once a depot exists and is not rubble, the base is established
        if !hasEstablishedBase {
            if !depots.isEmpty && depots.contains(where: { !$0.isDestroyed }) {
                hasEstablishedBase = true
            }
        }

        // 2. Strict Story Logic:
        // If the player has established a base and now all depots are gone, it's game over.
        // If hasEstablishedBase is false, the game waits (Setup/Grace mode).
        if hasEstablishedBase {
            let allDepotsDestroyed = depots.isEmpty || depots.allSatisfy({ $0.isDestroyed })
            
            if allDepotsDestroyed {
                isGameOver = true
                isVictory = false
                scene?.showGameOver(victory: false)
            }
        }
    }
    
    func checkVictory() {
        // Win condition: all bridges destroyed
        if map.getFunctionalBridges().isEmpty {
            isGameOver = true
            isVictory = true
            scene?.showGameOver(victory: true)
        }
    }
    
    func destroyBridge(id: Int) {
        if let bridge = map.bridges.first(where: { $0.id == id }) {
            map.destroyBridge(bridge)
            scene?.refreshTerrain()
            checkVictory()
        }
    }
}
