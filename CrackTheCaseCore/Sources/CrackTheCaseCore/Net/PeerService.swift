import Foundation

/// Bonjour service type shared by the host advertiser and client browser.
///
/// Must stay in sync with the `NSBonjourServices` entries
/// (`_crackthecase._tcp` / `_crackthecase._udp`) declared in both targets'
/// Info.plist, and must be 1-15 characters of lowercase ASCII letters,
/// numbers, and hyphens per `MCNearbyServiceAdvertiser` requirements.
enum PeerService {
    static let type = "crackthecase"
}
