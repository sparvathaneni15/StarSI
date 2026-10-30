// Live phone data the Macs can never have: location, Health, motion,
// camera. Only the current time ships today; CoreLocation / HealthKit /
// CoreMotion adapters arrive with the on-device model in Phase 4.

import Foundation

public enum LiveContext {
    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
