//
//  InterruptibilityEngine.swift
//  Project Apple
//
//  Loads ProjectAppleInterruptibility.mlmodel, builds the feature vector from
//  InterruptibilityRawFeatures, and returns an InterruptibilityResult.
//

import CoreML
import Foundation

// MARK: - Public types

enum NotificationAction: String {
    case sendNow     = "Send Now"
    case delay15Min  = "Delay 15 min"
    case digest      = "Digest"
}

/// All raw signal values the caller must supply before prediction.
struct InterruptibilityRawFeatures {
    /// Display name of the last opened tracked app, e.g. "Instagram", "WhatsApp".
    /// nil → all one-hot app columns stay 0 (treated as MISSING).
    var lastOpenApp: String?

    // Temporal features (caller computes from current Date)
    var hourSin: Double
    var hourCos: Double
    var isWeekend: Double               // 1.0 = weekend, 0.0 = weekday

    // Recency / activity features
    var opensLast15m: Double
    var opensLast60m: Double
    var switchesLast15m: Double
    var uniqueAppsLast24h: Double
    var timeSinceLastOpenMin: Double
    var historicalActivityScore: Double

    // Ping features
    var timeSinceLastPingMin: Double
    var pingsLast24h: Double

    /// Convenience initialiser with safe zero defaults for quick testing.
    static func sample() -> InterruptibilityRawFeatures {
        let now = Date()
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: now))
        let angle = hour / 24.0 * 2 * .pi
        let isWeekend: Double = [1, 7].contains(cal.component(.weekday, from: now)) ? 1.0 : 0.0
        return InterruptibilityRawFeatures(
            lastOpenApp: nil,
            hourSin: sin(angle),
            hourCos: cos(angle),
            isWeekend: isWeekend,
            opensLast15m: 0,
            opensLast60m: 0,
            switchesLast15m: 0,
            uniqueAppsLast24h: 0,
            timeSinceLastOpenMin: 30,
            historicalActivityScore: 0.5,
            timeSinceLastPingMin: 120,
            pingsLast24h: 0
        )
    }
}

struct InterruptibilityResult {
    let probabilityUsefulNow: Double   // 0…1
    let action: NotificationAction
    let explanation: String
}

enum InterruptibilityEngineError: Error, LocalizedError {
    case modelLoadFailed
    case predictionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:       return "Core ML model could not be loaded."
        case .predictionFailed(let msg): return "Prediction failed: \(msg)"
        }
    }
}

// MARK: - Engine

enum InterruptibilityEngine {

    // MARK: Feature names (source of truth for one-hot columns)

    /// Loaded once from ProjectApple_feature_names.json in the main bundle.
    private static let featureNames: [String] = {
        guard
            let url  = Bundle.main.url(forResource: "ProjectApple_feature_names",
                                       withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let list = try? JSONDecoder().decode([String].self, from: data)
        else {
            print("[InterruptibilityEngine] WARNING: feature_names.json not found; one-hot columns may be wrong.")
            return []
        }
        return list
    }()

    /// All "last_open_app_*" column names derived from the JSON.
    private static let appColumns: [String] = featureNames.filter { $0.hasPrefix("last_open_app_") }

    // MARK: Cached model

    /// The compiled Core ML model, loaded once on first access.
    ///
    /// Xcode auto-generates `ProjectAppleInterruptibility` from the .mlmodel.
    /// If the file is not yet added to the target, this will return nil and
    /// `predict` will throw `modelLoadFailed`.
    private static let cachedModel: ProjectAppleInterruptibility? = {
        do {
            return try ProjectAppleInterruptibility(configuration: MLModelConfiguration())
        } catch {
            print("[InterruptibilityEngine] Model load error: \(error)")
            return nil
        }
    }()

    // MARK: Prediction

    static func predict(_ raw: InterruptibilityRawFeatures) throws -> InterruptibilityResult {
        guard let model = cachedModel else { throw InterruptibilityEngineError.modelLoadFailed }

        // Build one-hot values for app columns.
        // The JSON is the source of truth for which columns exist.
        var chatGPT: Double    = 0
        var instagram: Double  = 0
        var whatsApp: Double   = 0

        if let app = raw.lastOpenApp {
            let key = "last_open_app_\(app)"
            switch key {
            case "last_open_app_ChatGPT":   chatGPT   = 1
            case "last_open_app_Instagram": instagram = 1
            case "last_open_app_WhatsApp":  whatsApp  = 1
            default:
                // App not in model columns → all-zeros (treated as MISSING).
                // If the model adds a "last_open_app_MISSING" column in future,
                // update the switch or derive it from `appColumns`.
                break
            }
        }

        // Build the typed input (auto-generated by Xcode from the .mlmodel).
        // Property names match the model's feature names exactly.
        let input = ProjectAppleInterruptibilityInput(
            hour_sin:                   raw.hourSin,
            hour_cos:                   raw.hourCos,
            is_weekend:                 raw.isWeekend,
            opens_last_15m:             raw.opensLast15m,
            opens_last_60m:             raw.opensLast60m,
            switches_last_15m:          raw.switchesLast15m,
            unique_apps_last_24h:       raw.uniqueAppsLast24h,
            time_since_last_open_min:   raw.timeSinceLastOpenMin,
            historical_activity_score:  raw.historicalActivityScore,
            time_since_last_ping_min:   raw.timeSinceLastPingMin,
            pings_last_24h:             raw.pingsLast24h,
            last_open_app_ChatGPT:      chatGPT,
            last_open_app_Instagram:    instagram,
            last_open_app_WhatsApp:     whatsApp
        )

        // Run prediction via the underlying MLModel to avoid key-type dependency
        // on classProbability (dictionary keys may be String or Int64 depending
        // on training label dtype; MLFeatureValue.dictionaryValue handles both).
        let provider: MLFeatureProvider
        do {
            provider = try model.model.prediction(from: input)
        } catch {
            throw InterruptibilityEngineError.predictionFailed(error.localizedDescription)
        }

        let prob = extractPositiveClassProbability(from: provider)
        let action = decideAction(prob: prob)
        let explanation = makeExplanation(raw: raw, prob: prob)

        return InterruptibilityResult(
            probabilityUsefulNow: prob,
            action: action,
            explanation: explanation
        )
    }

    // MARK: Helpers

    /// Extracts probability for the positive class ("1") from the output provider.
    /// Handles both String-keyed and Int64-keyed classProbability dictionaries.
    private static func extractPositiveClassProbability(from provider: MLFeatureProvider) -> Double {
        guard let fv = provider.featureValue(for: "classProbability") else { return 0.5 }
        let dict = fv.dictionaryValue  // [AnyHashable: NSNumber]

        // Try String key "1" (model trained with string labels "0"/"1")
        if let p = dict["1" as AnyHashable]?.doubleValue { return p }

        // Try NSNumber key 1 (model trained with integer labels 0/1)
        if let p = dict[NSNumber(value: Int64(1)) as AnyHashable]?.doubleValue { return p }

        // Last resort: invert the probability of class "0" / 0
        if let p0 = dict["0" as AnyHashable]?.doubleValue { return 1.0 - p0 }
        if let p0 = dict[NSNumber(value: Int64(0)) as AnyHashable]?.doubleValue { return 1.0 - p0 }

        return 0.5
    }

    private static func decideAction(prob: Double) -> NotificationAction {
        switch prob {
        case 0.65...: return .sendNow
        case 0.40...: return .delay15Min
        default:      return .digest
        }
    }

    /// Short deterministic explanation based on raw feature values and probability.
    private static func makeExplanation(raw: InterruptibilityRawFeatures, prob: Double) -> String {
        if raw.opensLast15m >= 3 || raw.switchesLast15m >= 2 {
            return "Recent activity is high"
        }
        if raw.timeSinceLastOpenMin < 3 {
            return "You were just on your phone"
        }
        if prob >= 0.65 {
            return "You usually engage around this hour"
        }
        if raw.timeSinceLastOpenMin > 60 && raw.opensLast60m == 0 {
            return "Low recent activity, better for digest"
        }
        if raw.pingsLast24h >= 4 {
            return "Several pings already sent today"
        }
        if raw.historicalActivityScore >= 0.7 {
            return "Historically active at this time"
        }
        return "Moderate activity detected"
    }
}
