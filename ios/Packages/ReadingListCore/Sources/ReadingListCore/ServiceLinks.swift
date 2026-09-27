import Foundation

// MARK: - Services & links
//
// Exact port of the web app's `serviceById` / `serviceFor` / `searchUrl` /
// `linkForIssue` / `isDirect` / `nextIssue` (assets/app.js lines 437-467).

public enum ServiceLinks {

    /// `entry.service || list.service`, resolved against the known services; falls
    /// back to the first known service when the id is not found.
    public static func service(for entry: Entry, in list: Playlist, services: [Service]) -> Service {
        let id = entry.service.isEmpty ? list.service : entry.service
        return services.first { $0.id == id } ?? services.first ?? Service.defaults[0]
    }

    /// Substitutes `{q}`, `{series}` and `{issue}` into the service's template,
    /// percent-encoding each substitution the way `encodeURIComponent` does. Returns
    /// "" when the template is not a safe http(s) URL.
    public static func searchURL(entry: Entry, issueLabel: String?, service: Service) -> String {
        let tpl = Sanitizer.safeURL(service.template, Limits.templateLength)
        guard !tpl.isEmpty else { return "" }

        let label = issueLabel ?? ""
        let q = [entry.series, label.isEmpty ? "" : "#" + label]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard tpl.contains("{q}") || tpl.contains("{series}") || tpl.contains("{issue}") else { return tpl }

        var result = tpl
        result = result.replacingOccurrences(of: "{q}", with: encodeURIComponent(q))
        result = result.replacingOccurrences(of: "{series}", with: encodeURIComponent(entry.series))
        result = result.replacingOccurrences(of: "{issue}", with: encodeURIComponent(label))
        return result
    }

    /// Pasted links win over the generated search, most specific first: an issue's
    /// own link, then the entry's, then the search.
    public static func link(for entry: Entry, issue: Issue?, in list: Playlist, services: [Service]) -> String {
        if let issue = issue, !issue.url.isEmpty { return issue.url }
        if !entry.url.isEmpty { return entry.url }
        let svc = service(for: entry, in: list, services: services)
        return searchURL(entry: entry, issueLabel: issue?.label, service: svc)
    }

    public static func isDirect(entry: Entry, issue: Issue?) -> Bool {
        if let issue = issue, !issue.url.isEmpty { return true }
        return !entry.url.isEmpty
    }

    public static func readURL(for entry: Entry, issue: Issue?, in list: Playlist, services: [Service]) -> URL? {
        URL(string: link(for: entry, issue: issue, in: list, services: services))
    }

    /// Equivalent to JavaScript's `encodeURIComponent`: everything but
    /// `A-Z a-z 0-9 - _ . ! ~ * ' ( )` is percent-encoded.
    public static func encodeURIComponent(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
