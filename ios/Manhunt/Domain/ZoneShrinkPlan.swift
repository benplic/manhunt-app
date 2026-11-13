import Foundation

struct ZoneShrinkVisual: Equatable {
    /// Radius of the solid play-area ring to draw right now.
    var radiusM: Double
    /// Radius of the dashed next-zone ring. Nil when there is nothing to preview.
    var nextRadiusM: Double?
    var previewOpacity: Double
}

enum ZoneShrinkPlan {
    /// The dashed ring appears when this share of the interval is left.
    static let previewStart = 0.5
    /// The solid ring contracts over this final share of the interval and lands on the dashed ring.
    static let contractionShare = 0.25
    /// Dashed ring fade-in length, as a share of the interval.
    static let fadeShare = 0.05

    static func visual(
        radiusM: Double,
        nextRadiusM: Double?,
        shrinksInS: Double?,
        intervalS: Double?
    ) -> ZoneShrinkVisual {
        let plain = ZoneShrinkVisual(radiusM: radiusM, nextRadiusM: nil, previewOpacity: 0)
        // TODO: servers older than the interval_s field send no interval. Show no preview for them.
        guard let next = nextRadiusM, next < radiusM,
              let shrinksIn = shrinksInS,
              let interval = intervalS, interval > 0
        else { return plain }
        let left = shrinksIn / interval
        guard left <= previewStart else { return plain }
        let opacity = min(1, max(0, (previewStart - left) / fadeShare))
        let progress = min(1, max(0, (contractionShare - left) / contractionShare))
        let eased = progress * progress * (3 - 2 * progress)
        return ZoneShrinkVisual(
            radiusM: radiusM + (next - radiusM) * eased,
            nextRadiusM: next,
            previewOpacity: opacity
        )
    }
}

/// Zone timer plus the anchor it arrived on, so the map can animate between snapshots.
struct ZoneShrinkClock: Equatable {
    var zone: ZoneTimerDTO
    var anchoredAt: Date
    var rate: Double

    func visual(at now: Date) -> ZoneShrinkVisual {
        let lead = ClockLead.seconds(rate: rate, anchoredAt: anchoredAt, now: now)
        return ZoneShrinkPlan.visual(
            radiusM: zone.radiusM,
            nextRadiusM: zone.nextRadiusM,
            shrinksInS: zone.shrinksInS.map { max(0, Double($0) - lead) },
            intervalS: zone.intervalS.map(Double.init)
        )
    }
}
