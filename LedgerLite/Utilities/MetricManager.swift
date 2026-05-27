import MetricKit

final class MetricManager: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricManager()

    override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            AppLogger.data.info("MetricKit metrics received: \(payload.jsonRepresentation())")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            AppLogger.data.fault("MetricKit crash/hang diagnostic: \(payload.jsonRepresentation())")
        }
    }
}
