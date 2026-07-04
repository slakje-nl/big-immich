import Foundation

func isValidHTTPURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else { return false }

    return url.host != nil
}
