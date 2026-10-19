import 'sha256.dart';

/// The one-way key under which everything account-specific is stored on this phone:
/// the first 32 hex digits of `sha256(installationId + ':' + userId)`.
///
/// * It is stable for one account on one installation, so signing back in finds
///   the receipts it left.
/// * It is different on every installation (the installation id is random and never
///   leaves the phone except as the device identity the server already knows), and
///   it cannot be turned back into the user id or the e-mail: neither of those is
///   ever written to the ledger tables or to `meta` by the sync code.
String accountKeyFor(String installationId, String userId) =>
    sha256Hex('$installationId:$userId').substring(0, 32);
