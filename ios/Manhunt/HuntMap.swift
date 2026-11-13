import MapKit
import SwiftUI

/// Shared map chrome for the live game and the arena editor.
struct HuntMap: View {
    var boundary: [VisualPoint]
    var boundaryCircle: CircleBoundary? = nil
    var zones: [VisualZone]
    var reveals: [MapReveal] = []
    var people: [VisualPlayer]
    var showHiders: Bool
    var showSeekers: Bool
    var fuzzyHiders: Bool
    var region: MKCoordinateRegion
    var pendingVertices: [VisualPoint] = []
    var pendingCircleCenter: VisualPoint? = nil
    var pendingCircleRadiusMeters: Double? = nil
    var highlightedEdge: (VisualPoint, VisualPoint)? = nil
    var homeCoordinate: CLLocationCoordinate2D? = nil
    /// Bumped once after the location sheet is answered so the camera leaves the fallback.
    var frameID: Int = 0
    var onDrop: ((VisualPoint) -> Void)?
    var onCrosshair: ((VisualPoint) -> Void)? = nil
    var emphasizeSpawn: Bool = false
    var glidePeople: Bool = false

    @State private var position: MapCameraPosition = .automatic
    @State private var crosshair = VisualPoint(latitude: 40.6616, longitude: -73.9688)
    @State private var glide = PlayerGlide()

    private var animates: Bool { glidePeople }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            mapContent(now: timeline.date)
        }
        .onAppear { glide.retarget(people, now: Date()) }
        .onChange(of: people) { _, updated in glide.retarget(updated, now: Date()) }
    }

    private func mapContent(now: Date) -> some View {
        Map(position: $position) {
                if let circle = boundaryCircle {
                    MapCircle(
                        center: CLLocationCoordinate2D(
                            latitude: circle.center.latitude,
                            longitude: circle.center.longitude
                        ),
                        radius: circle.radiusMeters
                    )
                    .foregroundStyle(HuntColor.signal.opacity(0.18))
                    .stroke(HuntColor.signal, lineWidth: 2)
                } else if boundary.count >= 3 {
                    MapPolygon(coordinates: boundary.map(\.coordinate))
                        .foregroundStyle(HuntColor.signal.opacity(0.18))
                        .stroke(HuntColor.signal, lineWidth: 2)
                } else if pendingVertices.count >= 2 {
                    MapPolyline(coordinates: pendingVertices.map(\.coordinate))
                        .stroke(HuntColor.signal, lineWidth: 2)
                }
                if let edge = highlightedEdge {
                    MapPolyline(coordinates: [edge.0.coordinate, edge.1.coordinate])
                        .stroke(HuntColor.paper, lineWidth: 4)
                }
                ForEach(Array(pendingVertices.enumerated()), id: \.offset) { _, point in
                    Annotation("Pending", coordinate: point.coordinate) {
                        Circle()
                            .fill(HuntColor.paper)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(HuntColor.ink, lineWidth: 2))
                    }
                }
                if let center = pendingCircleCenter {
                    if let radius = pendingCircleRadiusMeters, radius > 1 {
                        MapCircle(center: center.coordinate, radius: radius)
                            .foregroundStyle(HuntColor.signal.opacity(0.1))
                            .stroke(HuntColor.paper, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                    Annotation("Center", coordinate: center.coordinate) {
                        Circle()
                            .stroke(HuntColor.safe, lineWidth: 3)
                            .frame(width: 14, height: 14)
                    }
                }
                // Out zones paint last so a hole in a spawn or safe zone still reads as out.
                ForEach(zones.filter { $0.kind != .outOfBounds }) { zone in
                    zoneContent(zone)
                }
                ForEach(zones.filter { $0.kind == .outOfBounds }) { zone in
                    zoneContent(zone)
                }
                ForEach(reveals) { reveal in
                    revealContent(reveal)
                }
                if emphasizeSpawn {
                    ForEach(zones.filter { $0.kind == .spawn }) { zone in
                        if let anchor = zone.points.first {
                            Annotation("Locked spawn", coordinate: anchor.coordinate) {
                                Image(systemName: "lock.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(6)
                                    .background(HuntColor.ink, in: Circle())
                                    .foregroundStyle(HuntColor.paper)
                            }
                        }
                    }
                }
                ForEach(people) { person in
                    if shouldShow(person) {
                        Annotation(person.name, coordinate: displayPoint(for: person, now: now).coordinate, anchor: .center) {
                            PlayerPin(person: person, fuzzy: fuzzyHiders && person.role == .hider && !person.isYou)
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .continuous) { context in
                let center = context.region.center
                crosshair = VisualPoint(latitude: center.latitude, longitude: center.longitude)
                onCrosshair?(crosshair)
            }
            .overlay(alignment: .center) {
                if onDrop != nil {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(HuntColor.paper)
                        .shadow(color: .black.opacity(0.8), radius: 4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let onDrop {
                    VStack(spacing: 8) {
                        if let homeCoordinate {
                            Button {
                                let user = GeoPoint(
                                    latitude: homeCoordinate.latitude,
                                    longitude: homeCoordinate.longitude
                                )
                                frame(to: EditorCamera.region(user: user, boundary: [], isNew: true))
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(12)
                                    .background(HuntColor.inkRaised, in: Circle())
                                    .foregroundStyle(HuntColor.signal)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("My location")
                        }
                        Button {
                            onDrop(crosshair)
                        } label: {
                            Text("Drop point")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(HuntColor.paper, in: Capsule())
                                .foregroundStyle(HuntColor.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 12)
                }
            }
        .onAppear { frame(to: region) }
        .onChange(of: frameID) { _, _ in
            frame(to: region)
        }
    }

    /// One camera update. Callers pass EditorCamera.region so the span stays the editor default.
    private func frame(to region: MKCoordinateRegion) {
        position = .region(region)
        crosshair = VisualPoint(latitude: region.center.latitude, longitude: region.center.longitude)
        onCrosshair?(crosshair)
    }

    private func shouldShow(_ person: VisualPlayer) -> Bool {
        if person.role == .hider { return showHiders || person.isYou }
        if person.role == .seeker { return showSeekers || person.isYou }
        return person.isYou
    }

    /// Fuzzy pins are offset so the picture reads as "approximate", not exact.
    private func displayPoint(for person: VisualPlayer, now: Date) -> VisualPoint {
        let base = glidePeople ? (glide.point(for: person.id, at: now) ?? person.point) : person.point
        guard fuzzyHiders, person.role == .hider, !person.isYou else { return base }
        return VisualPoint(
            latitude: base.latitude + 0.00035,
            longitude: base.longitude - 0.00028
        )
    }

    @MapContentBuilder
    private func zoneContent(_ zone: VisualZone) -> some MapContent {
        let tint = tint(for: zone.kind)
        let width: CGFloat = (emphasizeSpawn && zone.kind == .spawn) ? 4 : 2
        if zone.kind == .safe, let center = zone.points.first, let radius = zone.radiusMeters {
            MapCircle(center: center.coordinate, radius: radius)
                .foregroundStyle(tint.opacity(0.28))
                .stroke(tint, lineWidth: width)
        } else if zone.points.count >= 3 {
            MapPolygon(coordinates: zone.points.map(\.coordinate))
                .foregroundStyle(tint.opacity(emphasizeSpawn && zone.kind == .spawn ? 0.45 : 0.28))
                .stroke(tint, lineWidth: width)
        } else if zone.points.count >= 2 {
            MapPolyline(coordinates: zone.points.map(\.coordinate))
                .stroke(tint, lineWidth: width)
        }
        if !zone.name.isEmpty,
           zone.kind == .safe || zone.kind == .outOfBounds || zone.kind == .spawn,
           let anchor = zone.points.first {
            Annotation(zone.name, coordinate: anchor.coordinate) {
                Text(zone.name)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(HuntColor.paper)
            }
        }
    }

    @MapContentBuilder
    private func revealContent(_ reveal: MapReveal) -> some MapContent {
        let color = RevealPalette.color(at: reveal.colorIndex)
        // Precise pins use radius 0. Any positive radius is a fuzzy circle.
        if reveal.radiusMeters > 0 {
            MapCircle(center: reveal.center.coordinate, radius: reveal.radiusMeters)
                .foregroundStyle(color.opacity(0.22))
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        Annotation(reveal.name, coordinate: reveal.center.coordinate) {
            RevealPin(name: reveal.name, color: color, fuzzy: reveal.radiusMeters > 0)
        }
    }

    private func tint(for kind: VisualZone.Kind) -> Color {
        switch kind {
        case .safe: HuntColor.safe
        case .outOfBounds: HuntColor.warning
        case .spawn: HuntColor.seeker
        }
    }
}

struct RevealPin: View {
    var name: String
    var color: Color
    var fuzzy: Bool

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: fuzzy ? 12 : 16, height: fuzzy ? 12 : 16)
            Text(name.split(separator: " ").first.map(String.init) ?? name)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.72), in: Capsule())
                .foregroundStyle(HuntColor.paper)
        }
    }
}

struct PlayerPin: View {
    var person: VisualPlayer
    var fuzzy: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(person.role.tint)
                    .frame(width: fuzzy ? 36 : 18, height: fuzzy ? 36 : 18)
                    .opacity(fuzzy ? 0.35 : 1)
                if !fuzzy {
                    Circle()
                        .stroke(HuntColor.paper, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            if !fuzzy {
                Text(person.isYou ? "You" : person.name.split(separator: " ").first.map(String.init) ?? person.name)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(HuntColor.paper)
            }
        }
    }
}
