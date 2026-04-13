//
//  AuthManager.swift
//  Project Apple
//

import Foundation
import FirebaseAuth

final class AuthManager {
    static let shared = AuthManager()

    private let appGroupId = "group.com.farzaan.projectapple"
    private let firebaseUidKey = "firebaseUid"

    private init() {}

    func ensureSignedIn() async throws -> String {
        if let currentUser = Auth.auth().currentUser {
            // Force-refresh the ID token so Firestore writes never fail with
            // "Missing or insufficient permissions" due to a stale token.
            _ = try await currentUser.getIDToken(forcingRefresh: true)
            persist(uid: currentUser.uid)
            return currentUser.uid
        }

        let uid = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let uid = result?.user.uid else {
                    continuation.resume(throwing: NSError(
                        domain: "AuthManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Anonymous sign-in returned no UID."]
                    ))
                    return
                }
                continuation.resume(returning: uid)
            }
        }

        persist(uid: uid)
        return uid
    }

    private func persist(uid: String) {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        defaults.set(uid, forKey: firebaseUidKey)
    }
}
