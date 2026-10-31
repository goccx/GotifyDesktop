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
    private func relativeText(referenceDate: Date) -> String {
        RelativeDateTimeFormatterCache.string(for: date, relativeTo: referenceDate, locale: locale, unitsStyle: .abbreviated)
    }

    /// VoiceOver receives an unabridged version instead of reading a compact unit ambiguously.
    private func accessibilityText(referenceDate: Date) -> String {
        RelativeDateTimeFormatterCache.string(for: date, relativeTo: referenceDate, locale: locale, unitsStyle: .full)
    }

    /// The compact label keeps the list calm; the standard macOS hover affordance exposes the exact time.
    private var absoluteText: String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                timeZone: TimeZone.autoupdatingCurrent
            )
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}

/// Keeps full absolute timestamps consistent across list and detail while forcing a 24-hour clock.
enum MessageAbsoluteTimeFormat {
    static func listTime(_ date: Date, locale: Locale) -> String {
        formatted(date, locale: locale)
    }

    static func detailTime(_ date: Date, locale: Locale) -> String {
        formatted(date, locale: locale)
    }

    /// Date components follow the in-app language; the current macOS time zone and 24-hour time remain unchanged.
    private static func formatted(_ date: Date, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                timeZone: TimeZone.autoupdatingCurrent
            )
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
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
