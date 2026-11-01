import Foundation
import SwiftUI

/// A localized relative timestamp that refreshes only while this individual label remains mounted.
///
/// The cadence matches Gotify Web's `react-timeago`: seconds below one minute, then minutes, hours,
/// and weeks. `TimelineView` owns scheduling, so there is no process-wide polling task and off-screen
/// list rows do not keep a refresh task alive.
struct RelativeTimeLabel: View {
    let date: Date
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(RelativeTimeTimelineSchedule(eventDate: date)) { context in
            Text(relativeText(referenceDate: context.date))
                .accessibilityLabel(accessibilityText(referenceDate: context.date))
                .help(absoluteText)
        }
    }

    /// Foundation owns pluralization, locale grammar, future dates, and calendar-boundary behavior.
    static func relativeString(for date: Date, relativeTo referenceDate: Date, locale: Locale) -> String {
        RelativeDateTimeFormatterCache.string(for: date, relativeTo: referenceDate, locale: locale, unitsStyle: .abbreviated)
    }

    /// VoiceOver receives an unabridged version instead of reading a compact unit ambiguously.
    static func accessibilityString(for date: Date, relativeTo referenceDate: Date, locale: Locale) -> String {
        RelativeDateTimeFormatterCache.string(for: date, relativeTo: referenceDate, locale: locale, unitsStyle: .full)
    }

    private func relativeText(referenceDate: Date) -> String {
        Self.relativeString(for: date, relativeTo: referenceDate, locale: locale)
    }

    private func accessibilityText(referenceDate: Date) -> String {
        Self.accessibilityString(for: date, relativeTo: referenceDate, locale: locale)
    }

    /// The compact label keeps the list calm; the standard macOS hover affordance exposes the exact time.
    private var absoluteText: String {
        MessageAbsoluteTimeFormat.listTime(date, locale: locale)
    }
}

/// Keeps full absolute timestamps consistent across list and detail while forcing a 24-hour clock.
enum MessageAbsoluteTimeFormat {
    private struct CacheKey: Hashable {
        let minuteBucket: Int64
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    private static let lock = NSLock()
    private static var styleByLocale: [String: Date.FormatStyle] = [:]
    private static var formattedCache: [CacheKey: String] = [:]

    static func listTime(_ date: Date, locale: Locale) -> String {
        formatted(date, locale: locale)
    }

    static func detailTime(_ date: Date, locale: Locale) -> String {
        formatted(date, locale: locale)
    }

    /// Date components follow the in-app language; the current macOS time zone and 24-hour time remain unchanged.
    private static func formatted(_ date: Date, locale: Locale) -> String {
        lock.lock()
        defer { lock.unlock() }

        let timeZone = TimeZone.autoupdatingCurrent
        let minuteBucket = Int64(floor(date.timeIntervalSince1970 / 60.0))
        let cacheKey = CacheKey(
            minuteBucket: minuteBucket,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier
        )
        if let cached = formattedCache[cacheKey] {
            return cached
        }

        let styleKey = "\(locale.identifier)|\(timeZone.identifier)"
        let style: Date.FormatStyle
        if let existing = styleByLocale[styleKey] {
            style = existing
        } else {
            let created = Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                timeZone: timeZone
            )
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
            styleByLocale[styleKey] = created
            style = created
        }

        let result = date.formatted(style)
        if formattedCache.count >= 1_024 {
            formattedCache.removeAll(keepingCapacity: true)
        }
        formattedCache[cacheKey] = result
        return result
    }
}

/// Produces the next meaningful visual transition instead of waking every label at a fixed rate.
private struct RelativeTimeTimelineSchedule: TimelineSchedule {
    let eventDate: Date

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(eventDate: eventDate, nextDate: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let eventDate: Date
        private var nextDate: Date

        init(eventDate: Date, nextDate: Date) {
            self.eventDate = eventDate
            self.nextDate = nextDate
        }

        mutating func next() -> Date? {
            let entry = nextDate
            nextDate = entry.addingTimeInterval(refreshInterval(referenceDate: entry))
            return entry
        }

        /// Keep recent delivery feedback responsive without wasting wakeups on older timestamps.
        private func refreshInterval(referenceDate: Date) -> TimeInterval {
            let age = abs(referenceDate.timeIntervalSince(eventDate))

            return switch age {
            case ..<60:
                1
            case ..<3_600:
                60
            case ..<86_400:
                3_600
            default:
                604_800
            }
        }
    }
}

/// Caches `RelativeDateTimeFormatter` instances per locale and unit style so list row rendering
/// does not allocate new ICU formatters on every SwiftUI body evaluation.
private enum RelativeDateTimeFormatterCache {
    private struct Key: Hashable {
        let localeIdentifier: String
        let unitsStyleRawValue: Int
    }

    private static let lock = NSLock()
    private static var formatters: [Key: RelativeDateTimeFormatter] = [:]

    static func string(
        for date: Date,
        relativeTo referenceDate: Date,
        locale: Locale,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        let key = Key(localeIdentifier: locale.identifier, unitsStyleRawValue: unitsStyle.rawValue)
        let formatter: RelativeDateTimeFormatter
        if let existing = formatters[key] {
            formatter = existing
        } else {
            let created = RelativeDateTimeFormatter()
            created.locale = locale
            created.unitsStyle = unitsStyle
            formatters[key] = created
            formatter = created
        }
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
