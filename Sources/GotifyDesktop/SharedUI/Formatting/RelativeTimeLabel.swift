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
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    /// VoiceOver receives an unabridged version instead of reading a compact unit ambiguously.
    private func accessibilityText(referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
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
