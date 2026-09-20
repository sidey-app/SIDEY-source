import AppKit

struct EdgeTrackGeometry: Equatable, Sendable {
    static let characterPointSize: CGFloat = 48
    static let hotspotPointSize: CGFloat = 52
    static let footInset: CGFloat = characterPointSize / 2
        - CGFloat(PixelCharacterCatalog.footBaselinePixel) * 2

    let bounds: CGRect
    let edge: OverlayEdge

    var tangentLength: CGFloat { edge.isHorizontal ? bounds.width : bounds.height }

    var trackRange: ClosedRange<CGFloat> {
        let inset = min(Self.hotspotPointSize / 2, max(0, tangentLength / 2))
        return inset...(max(inset, tangentLength - inset))
    }

    func point(for tangent: CGFloat) -> CGPoint {
        let value = clamped(tangent)
        return switch edge {
        case .bottom:
            CGPoint(x: bounds.minX + value, y: bounds.minY + Self.footInset)
        case .top:
            CGPoint(x: bounds.minX + value, y: bounds.maxY - Self.footInset)
        case .left:
            CGPoint(x: bounds.minX + Self.footInset, y: bounds.minY + value)
        case .right:
            CGPoint(x: bounds.maxX - Self.footInset, y: bounds.minY + value)
        }
    }

    func footPoint(for tangent: CGFloat) -> CGPoint {
        let anchor = point(for: tangent)
        let localFoot = CGPoint(x: 0, y: -Self.footInset)
        let cosine = cos(edge.presentationRotation)
        let sine = sin(edge.presentationRotation)
        return CGPoint(
            x: anchor.x + localFoot.x * cosine - localFoot.y * sine,
            y: anchor.y + localFoot.x * sine + localFoot.y * cosine
        )
    }

    func worldFrame(for localFrame: CGRect, at tangent: CGFloat) -> CGRect {
        let anchor = point(for: tangent)
        let transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .rotated(by: edge.presentationRotation)
        return localFrame.applying(transform)
    }

    func clamped(_ tangent: CGFloat) -> CGFloat {
        let finite = tangent.isFinite ? tangent : trackRange.lowerBound
        return min(max(finite, trackRange.lowerBound), trackRange.upperBound)
    }
}
struct PixelMovementAgent: Equatable, Identifiable, Sendable {
    let id: UUID
    var trackPosition: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    var idleRemaining: TimeInterval = 0
    var messageBubbleSeparationOrder: CGFloat? = nil
}

enum PixelMovementPolicy {
    static func stoppedMemberIDs(in members: some Sequence<PixelWorldMember>) -> Set<UUID> {
        Set(members.compactMap { member in
            switch member.presence {
            case .away, .offline, .reconnecting:
                member.id
            case .online, .typing:
                nil
            }
        })
    }
}

enum PixelWorldAvoidanceLayout {
    static let composerSize = CGSize(width: 440, height: 76)

    static func composerRects(
        activityFrame: CGRect,
        edge: OverlayEdge,
        composerVisible: Bool,
        composerFrame: CGRect? = nil
    ) -> [CGRect] {
        guard composerVisible else { return [] }
        if let composerFrame {
            let rect = composerFrame.insetBy(dx: -20, dy: -10).intersection(activityFrame)
            return rect.isNull || rect.isEmpty ? [] : [rect]
        }
        guard edge == .top else { return [] }
        let rect = CGRect(
            x: activityFrame.midX - composerSize.width / 2,
            y: activityFrame.maxY - composerSize.height,
            width: composerSize.width,
            height: composerSize.height
        ).intersection(activityFrame)
        return rect.isNull || rect.isEmpty ? [] : [rect]
    }

    static func composerRects(
        worldSize: CGSize,
        edge: OverlayEdge,
        composerVisible: Bool
    ) -> [CGRect] {
        composerRects(
            activityFrame: CGRect(origin: .zero, size: worldSize),
            edge: edge,
            composerVisible: composerVisible
        )
    }
}

enum PixelMovementSimulation {
    static let characterRadius: CGFloat = 25
    static let maximumSpeed: CGFloat = 22
    static let overlapMaximumSpeed: CGFloat = 30
    static let overlapForwardAcceleration: CGFloat = 64
    static let messageBubbleClearance: CGFloat = 8
    static let messageBubbleMaximumSpeed: CGFloat = 72
    static let messageBubbleSeparationAcceleration: CGFloat = 240

    static func step(
        agents: inout [PixelMovementAgent],
        deltaTime rawDeltaTime: TimeInterval,
        geometry: EdgeTrackGeometry,
        avoidanceRects: [CGRect],
        stoppedIDs: Set<UUID>,
        messageBubbleTangentRanges: [UUID: ClosedRange<CGFloat>] = [:]
    ) {
        guard !agents.isEmpty, geometry.tangentLength.isFinite else { return }
        let deltaTime = min(max(rawDeltaTime, 0), 1.0 / 10.0)
        guard deltaTime > 0 else { return }

        var separation: [UUID: CGFloat] = [:]
        var overlappingIDs: Set<UUID> = []
        for lhsIndex in agents.indices {
            for rhsIndex in agents.indices where rhsIndex > lhsIndex {
                let lhs = agents[lhsIndex]
                let rhs = agents[rhsIndex]
                let delta = lhs.trackPosition - rhs.trackPosition
                let distance = abs(delta)
                let desiredDistance = characterRadius * 2
                guard distance < desiredDistance else { continue }
                let direction: CGFloat
                if distance > 0.001 {
                    direction = delta < 0 ? -1 : 1
                } else {
                    direction = lhs.id.uuidString < rhs.id.uuidString ? -1 : 1
                }
                let strength = max(0, 1 - distance / desiredDistance) * 30
                separation[lhs.id, default: 0] += direction * strength
                separation[rhs.id, default: 0] -= direction * strength
                overlappingIDs.insert(lhs.id)
                overlappingIDs.insert(rhs.id)
            }
        }

        var messageBubbleCollisionPairs: [(UUID, UUID)] = []
        var messageBubbleSeparatingIDs: Set<UUID> = []
        for lhsIndex in agents.indices {
            for rhsIndex in agents.indices where rhsIndex > lhsIndex {
                let lhs = agents[lhsIndex]
                let rhs = agents[rhsIndex]
                guard let lhsRange = messageBubbleTangentRanges[lhs.id],
                      let rhsRange = messageBubbleTangentRanges[rhs.id],
                      lhsRange.lowerBound.isFinite,
                      lhsRange.upperBound.isFinite,
                      rhsRange.lowerBound.isFinite,
                      rhsRange.upperBound.isFinite
                else { continue }

                let gap = max(lhsRange.lowerBound, rhsRange.lowerBound)
                    - min(lhsRange.upperBound, rhsRange.upperBound)
                guard gap < messageBubbleClearance else { continue }

                messageBubbleCollisionPairs.append((lhs.id, rhs.id))
                messageBubbleSeparatingIDs.insert(lhs.id)
                messageBubbleSeparatingIDs.insert(rhs.id)
            }
        }

        for index in agents.indices {
            if messageBubbleSeparatingIDs.contains(agents[index].id) {
                if agents[index].messageBubbleSeparationOrder == nil {
                    agents[index].messageBubbleSeparationOrder = agents[index].trackPosition
                }
            } else {
                agents[index].messageBubbleSeparationOrder = nil
            }
        }

        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var messageBubbleSeparation: [UUID: CGFloat] = [:]
        var blockedForceTransfers: [(recipientID: UUID, force: CGFloat)] = []
        for (lhsID, rhsID) in messageBubbleCollisionPairs {
            guard let lhs = agentsByID[lhsID], let rhs = agentsByID[rhsID] else { continue }
            let lhsOrder = lhs.messageBubbleSeparationOrder ?? lhs.trackPosition
            let rhsOrder = rhs.messageBubbleSeparationOrder ?? rhs.trackPosition
            let lhsIsLeft = if abs(lhsOrder - rhsOrder) > 0.001 {
                lhsOrder < rhsOrder
            } else {
                lhs.id.uuidString < rhs.id.uuidString
            }
            let left = lhsIsLeft ? lhs : rhs
            let right = lhsIsLeft ? rhs : lhs
            let leftCanMove = canMove(
                agentsByID[left.id],
                direction: -1,
                stoppedIDs: stoppedIDs,
                trackRange: geometry.trackRange
            )
            let rightCanMove = canMove(
                agentsByID[right.id],
                direction: 1,
                stoppedIDs: stoppedIDs,
                trackRange: geometry.trackRange
            )

            messageBubbleSeparation[left.id, default: 0] -= messageBubbleSeparationAcceleration
            messageBubbleSeparation[right.id, default: 0] += messageBubbleSeparationAcceleration
            switch (leftCanMove, rightCanMove) {
            case (true, false):
                blockedForceTransfers.append((left.id, -messageBubbleSeparationAcceleration))
            case (false, true):
                blockedForceTransfers.append((right.id, messageBubbleSeparationAcceleration))
            case (true, true), (false, false):
                break
            }
        }
        let untransferredSeparation = messageBubbleSeparation
        for transfer in blockedForceTransfers {
            let existingForce = untransferredSeparation[transfer.recipientID, default: 0]
            guard existingForce * transfer.force > 0 else { continue }
            messageBubbleSeparation[transfer.recipientID, default: 0] += transfer.force
        }
        for agent in agents {
            let force = messageBubbleSeparation[agent.id, default: 0]
            guard abs(force) > 0.001 else { continue }
            if !canMove(
                agent,
                direction: force,
                stoppedIDs: stoppedIDs,
                trackRange: geometry.trackRange
            ) {
                messageBubbleSeparation[agent.id] = 0
            }
        }

        for index in agents.indices {
            var agent = agents[index]
            guard !stoppedIDs.contains(agent.id) else {
                agent.velocity = 0
                agents[index] = agent
                continue
            }
            let isOverlapping = overlappingIDs.contains(agent.id)
            let isSeparatingMessageBubbles = messageBubbleSeparatingIDs.contains(agent.id)
            if agent.idleRemaining > 0, !isOverlapping, !isSeparatingMessageBubbles {
                agent.idleRemaining = max(0, agent.idleRemaining - deltaTime)
                agent.velocity = 0
                agents[index] = agent
                continue
            }
            if isOverlapping || isSeparatingMessageBubbles {
                agent.idleRemaining = 0
            }

            if isSeparatingMessageBubbles {
                var acceleration = messageBubbleSeparation[agent.id, default: 0]
                for rect in avoidanceRects {
                    acceleration += avoidanceForce(
                        trackPosition: agent.trackPosition,
                        geometry: geometry,
                        rect: rect
                    )
                }
                if abs(acceleration) <= 0.001 {
                    agent.velocity = 0
                } else {
                    agent.velocity += acceleration * CGFloat(deltaTime)
                    agent.velocity = min(
                        max(agent.velocity, -messageBubbleMaximumSpeed),
                        messageBubbleMaximumSpeed
                    )
                    agent.trackPosition = geometry.clamped(
                        agent.trackPosition + agent.velocity * CGFloat(deltaTime)
                    )
                }
                if !agent.trackPosition.isFinite || !agent.velocity.isFinite {
                    agent.trackPosition = geometry.trackRange.lowerBound
                    agent.velocity = 0
                }
                agents[index] = agent
                continue
            }

            let delta = agent.target - agent.trackPosition
            let targetDirection: CGFloat = if abs(delta) > 2 {
                delta < 0 ? -1 : 1
            } else if abs(agent.velocity) > 0.1 {
                agent.velocity < 0 ? -1 : 1
            } else {
                separation[agent.id, default: 0] < 0 ? -1 : 1
            }
            var acceleration: CGFloat = abs(delta) > 2 ? targetDirection * 32 : 0
            let separationForce = separation[agent.id, default: 0]
            if isOverlapping {
                // The one-dimensional track has no room for a side-step. When
                // separation opposes travel, head-on characters otherwise stick
                // together, so accelerate through while preserving direction.
                acceleration += targetDirection * overlapForwardAcceleration
                if separationForce * targetDirection > 0 {
                    acceleration += separationForce
                }
            } else {
                acceleration += separationForce
            }
            for rect in avoidanceRects {
                acceleration += avoidanceForce(
                    trackPosition: agent.trackPosition,
                    geometry: geometry,
                    rect: rect
                )
            }

            agent.velocity += acceleration * CGFloat(deltaTime)
            let damping: CGFloat = isOverlapping ? 0.92 : 0.82
            agent.velocity *= pow(damping, CGFloat(deltaTime * 30))
            let speedLimit = isOverlapping ? overlapMaximumSpeed : maximumSpeed
            agent.velocity = min(max(agent.velocity, -speedLimit), speedLimit)
            agent.trackPosition = geometry.clamped(agent.trackPosition + agent.velocity * CGFloat(deltaTime))

            if !agent.trackPosition.isFinite || !agent.velocity.isFinite {
                agent.trackPosition = geometry.trackRange.lowerBound
                agent.velocity = 0
            }
            agents[index] = agent
        }
    }

    private static func canMove(
        _ agent: PixelMovementAgent?,
        direction: CGFloat,
        stoppedIDs: Set<UUID>,
        trackRange: ClosedRange<CGFloat>
    ) -> Bool {
        guard let agent, !stoppedIDs.contains(agent.id) else { return false }
        if direction < 0 {
            return agent.trackPosition > trackRange.lowerBound + 0.001
        }
        return agent.trackPosition < trackRange.upperBound - 0.001
    }

    private static func avoidanceForce(
        trackPosition: CGFloat,
        geometry: EdgeTrackGeometry,
        rect: CGRect
    ) -> CGFloat {
        let expanded = rect.insetBy(dx: -characterRadius, dy: -characterRadius)
        let point = geometry.point(for: trackPosition)
        guard expanded.contains(point) else { return 0 }
        let lower = geometry.edge.isHorizontal
            ? expanded.minX - geometry.bounds.minX
            : expanded.minY - geometry.bounds.minY
        let upper = geometry.edge.isHorizontal
            ? expanded.maxX - geometry.bounds.minX
            : expanded.maxY - geometry.bounds.minY
        return trackPosition - lower < upper - trackPosition ? -90 : 90
    }
}
